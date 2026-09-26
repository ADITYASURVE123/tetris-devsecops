// Jenkins = CI (build, test, scan, push image)
// ArgoCD  = CD (watches the k8s-manifests repo and syncs to EKS)
// Jenkins' only job at the end is to bump the image tag in the manifests repo -
// it never talks to the cluster directly. That separation is the point of GitOps.

pipeline {
    agent any

    environment {
        AWS_REGION    = 'ap-south-1'
        DOCKER_REPO   = 'adityasurve/tetris-app'
        MANIFEST_REPO = 'git@github.com:ADITYASURVE123/tetris-devsecops.git'
        // SONAR_HOST    = credentials('sonar-host-url') // Uncomment when credential is configured
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    def gitHash = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${gitHash}"
                }
            }
        }

        stage('SCA: Dependency Check') {
            steps {
                sh '''
                  # Software Composition Analysis on package manifests
                  trivy fs --scanners vuln,secret,misconfig \
                    --severity HIGH,CRITICAL \
                    --exit-code 0 \
                    --format table \
                    -o trivy-fs-report.txt .
                '''
            }
            post {
                always { archiveArtifacts artifacts: 'trivy-fs-report.txt', allowEmptyArchive: true }
            }
        }

        stage('SAST') {
            steps {
                echo 'Run SonarQube / Semgrep here for static analysis on app code.'
                // sh 'semgrep --config=auto app/ || true'
            }
        }

        stage('Build Image') {
            steps {
                sh "docker build -t ${DOCKER_REPO}:${IMAGE_TAG} ."
            }
        }

        stage('Trivy: Image Scan') {
            steps {
                sh """
                  trivy image \
                    --severity HIGH,CRITICAL \
                    --exit-code 0 \
                    --format table \
                    -o trivy-image-report.txt \
                    ${DOCKER_REPO}:${IMAGE_TAG}
                """
            }
            post {
                always { archiveArtifacts artifacts: 'trivy-image-report.txt', allowEmptyArchive: true }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', passwordVariable: 'DOCKER_PASS', usernameVariable: 'DOCKER_USER')]) {
                    sh """
                      echo "\$DOCKER_PASS" | docker login -u "\$DOCKER_USER" --password-stdin
                      docker push ${DOCKER_REPO}:${IMAGE_TAG}
                    """
                }
            }
        }

        stage('GitOps: Bump Image Tag') {
            steps {
                sshagent(['github-deploy-key']) {
                    sh """
                      set -e
                      rm -rf manifests-checkout
                      
                      # Disable host key checks for non-interactive SSH clone
                      GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
                        git clone ${MANIFEST_REPO} manifests-checkout
                      
                      cd manifests-checkout

                      # Detect target branch dynamically (main or master)
                      BRANCH=\$(git symbolic-ref --short HEAD || echo "main")

                      # Update deployment manifest
                      sed -i "s|image:.*tetris-app.*|image: ${DOCKER_REPO}:${IMAGE_TAG}|" k8s/base/deployment.yaml

                      # Configure Git User
                      git config user.email "jenkins@ci"
                      git config user.name "jenkins-ci"

                      # Commit and Push
                      git commit -am "ci: bump tetris-app to ${IMAGE_TAG}" || echo "No changes to commit"
                      
                      GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
                        git push origin \$BRANCH
                    """
                }
            }
        }
    }

    post {
        always {
            // Clean up local Docker image after completion to save disk space
            sh "docker rmi ${DOCKER_REPO}:${IMAGE_TAG} || true"
        }
        success { echo "Image ${DOCKER_REPO}:${IMAGE_TAG} built, scanned, and handed to ArgoCD." }
        failure { echo "Pipeline failed - check build logs and Trivy reports." }
    }
}
