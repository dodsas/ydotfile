---
name: jenkins-push-deploy
description: git push → Jenkins → SSH → 원격 podman-compose 5-stage 자동배포 파이프라인을 만들 때 사용. webhook 가능/불가 환경 모두 대응, SSH 자격증명 재사용, 브랜치 가드 포함. 사내망 / 단일 호스트 운영에 적합.
---

# Jenkins Push-Deploy 파이프라인 (Checkout → Package → Transfer → Deploy → Smoke)

이 레포 `Jenkinsfile` + `deploy/deploy.sh` 의 패턴. 외부 레지스트리 없이도 동작하는 미니멀 CD.

## 흐름

```
git push origin main
     │
     ▼
Jenkins (webhook 또는 pollSCM)
     │
     ▼
Checkout ──> Package (git archive) ──> Transfer (scp+ssh+tar) ──> Deploy (deploy.sh) ──> Smoke (curl /health)
```

이미지 레지스트리 불필요. `git archive` 로 tar.gz 만들어 SCP, 원격에서 `podman-compose build` 가 그 자리에서 이미지 생성.

## 파라미터 vs environment 분리 원칙

- **parameters** : 환경마다 달라지는 값 (`DEPLOY_HOST`, `DEPLOY_USER`, `REMOTE_DIR`, `DEPLOY_BRANCH`)
- **environment** : 운영 표준 고정값 (`APP_NAME`, `SSH_CRED`, `SSH_PORT`, `HOST_PORT`)
- 함정: `HOST_PORT` 같은 값을 parameters 에 두면 Jenkins 파라미터 캐시가 옛값 들고 있어 변경이 안 먹는 사례 있음 → environment 로 옮기는 게 안전

## Jenkinsfile 골격

```groovy
pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds(); buildDiscarder(logRotator(numToKeepStr: '20')) }

  parameters {
    string(name: 'DEPLOY_HOST', defaultValue: 'host.example.com', description: '배포 대상')
    string(name: 'DEPLOY_USER', defaultValue: 'deploy', description: 'SSH 사용자')
    string(name: 'REMOTE_DIR', defaultValue: '/home/deploy/work/myapp', description: '원격 작업 디렉토리')
    string(name: 'DEPLOY_BRANCH', defaultValue: 'main', description: '자동 배포 대상 브랜치')
  }

  environment {
    APP_NAME = 'myapp'
    SSH_CRED = 'shared-deploy-ssh'   // 사내 공용 credential 재사용
    SSH_PORT = '22'
    HOST_PORT = '8080'
  }

  triggers {
    githubPush()                // webhook 가능 환경
    pollSCM('H/2 * * * *')      // fallback / 사내망
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.GIT_BRANCH_NAME = sh(returnStdout: true, script: "git rev-parse --abbrev-ref HEAD").trim()
          env.GIT_SHORT_SHA = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
          env.IMAGE_TAG = "b${BUILD_NUMBER}-${env.GIT_SHORT_SHA}"
        }
      }
    }

    stage('Build & Deploy') {
      when {
        anyOf {
          expression { env.BRANCH_NAME == params.DEPLOY_BRANCH }
          expression { env.GIT_BRANCH_NAME == params.DEPLOY_BRANCH }
          // detached HEAD 케이스 (script from SCM 단일 브랜치 빌드)
          expression { env.BRANCH_NAME == null && env.GIT_BRANCH_NAME == 'HEAD' }
        }
      }
      stages {
        stage('Package') {
          steps { sh 'git archive --format=tar.gz --output=${APP_NAME}.tar.gz HEAD' }
        }
        stage('Transfer') {
          steps {
            withCredentials([sshUserPrivateKey(credentialsId: env.SSH_CRED, keyFileVariable: 'SSH_KEY')]) {
              sh '''
                SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"
                ssh -p ${SSH_PORT} ${SSH_OPTS} ${DEPLOY_USER}@${DEPLOY_HOST} "mkdir -p ${REMOTE_DIR}"
                scp -P ${SSH_PORT} ${SSH_OPTS} ${APP_NAME}.tar.gz ${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_DIR}/
                ssh -p ${SSH_PORT} ${SSH_OPTS} ${DEPLOY_USER}@${DEPLOY_HOST} "
                  cd ${REMOTE_DIR} && tar -xzf ${APP_NAME}.tar.gz && rm -f ${APP_NAME}.tar.gz && chmod +x deploy/*.sh
                "
              '''
            }
          }
        }
        stage('Deploy') {
          steps {
            withCredentials([sshUserPrivateKey(credentialsId: env.SSH_CRED, keyFileVariable: 'SSH_KEY')]) {
              sh '''
                ssh -p ${SSH_PORT} -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new ${DEPLOY_USER}@${DEPLOY_HOST} "
                  export APP_NAME=${APP_NAME} APP_DIR=${REMOTE_DIR} HOST_PORT=${HOST_PORT} IMAGE_TAG=${IMAGE_TAG}
                  bash ${REMOTE_DIR}/deploy/deploy.sh
                "
              '''
            }
          }
        }
        stage('Smoke Test') {
          steps {
            withCredentials([sshUserPrivateKey(credentialsId: env.SSH_CRED, keyFileVariable: 'SSH_KEY')]) {
              sh 'ssh -p ${SSH_PORT} -i ${SSH_KEY} ${DEPLOY_USER}@${DEPLOY_HOST} "curl -fsS http://127.0.0.1:${HOST_PORT}/health"'
            }
          }
        }
      }
    }
  }

  post {
    always { sh 'rm -f ${APP_NAME}.tar.gz || true' }
  }
}
```

## webhook vs pollSCM 선택

- 외부에서 Jenkins URL 접근 가능 → **webhook** (`githubPush()`). 즉시 트리거.
- 사내망 / 방화벽 → **pollSCM('H/2 * * * *')**. 최대 2분 지연이지만 무인 배포 동작.
- 둘 다 켜두면 webhook 이 1차, polling 이 backup. 단점 없음.

## SSH credential 재사용

- 여러 서비스가 같은 호스트의 같은 계정에 배포한다면 credential ID 한 개로 통일 (예: `shared-deploy-ssh`). 키 회전이 1회로 끝남.
- 분리가 필요해지면 그때 새 ID 만들고 `SSH_CRED` 만 교체. 변경 1줄.

## 자주 막히는 지점

| 증상 | 원인 |
|---|---|
| `when` 가드에 안 걸려서 deploy 스킵 | `BRANCH_NAME` vs `GIT_BRANCH_NAME` vs `HEAD` 분기 누락 — 위 골격처럼 3가지 다 체크 |
| webhook 정상인데 빌드 안 시작 | Jenkins 의 GitHub plugin 미설치, 또는 Item 의 trigger 체크박스 빠뜨림 |
| `permission denied (publickey)` | credentials 의 키가 원격 `authorized_keys` 에 없음. SELinux 켜진 경우 `restorecon -Rv ~/.ssh` |
| smoke test 502 | 헬스체크 대기 (deploy.sh 의 30초 루프) 가 짧음. 첫 빌드는 30s 부족할 수 있음 |
| pollSCM 이 무한 trigger | `H/2 * * * *` 의 `H` 빠뜨려서 정확히 같은 시각에 모든 job 폴링 → 부하 |

## 롤백

이미지 태그 보관 안 하므로 **git revert + push** 가 정공. 빌드별 태그가 필요해지면:
```groovy
sh 'podman tag localhost/${APP_NAME}:latest localhost/${APP_NAME}:${IMAGE_TAG}'
```
한 줄 추가 + 보관 정책(IMAGE_RETAIN) 정의.
