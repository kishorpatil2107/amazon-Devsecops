pipeline {
    agent any

    tools {
        jdk 'jdk17'
        nodejs 'node16'
    }

    environment {
        SCANNER_HOME   = tool 'sonar-scanner'
        IMAGE_NAME     = "amazon"
        DOCKER_USER    = "harishnshetty"
        SONAR_PROJECT  = "amazon"
        NVD_API_KEY    = credentials('nvd-api-key')

        // Persistent caches
        TRIVY_CACHE    = "/var/lib/jenkins/trivy-cache"
        ODC_CACHE      = "/var/lib/jenkins/odc-cache"
    }

    stages {
        stage("Checkout Code") {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[url: 'https://github.com/kishorpatil2107/amazon-Devsecops.git']],
                    extensions: [[$class: 'CleanBeforeCheckout']]
                ])
            }
        }

        stage("SonarQube Analysis") {
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh ''' $SCANNER_HOME/bin/sonar-scanner \
                        -Dsonar.projectName=$SONAR_PROJECT \
                        -Dsonar.projectKey=$SONAR_PROJECT '''
                }
            }
        }

        stage("Quality Gate") {
            steps {
                script {
                    timeout(time: 3, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: false, credentialsId: 'sonar-token'
                    }
                }
            }
        }

        stage("Install Dependencies") {
            steps {
                sh '''
                  mkdir -p ~/.npm
                  npm ci --prefer-offline --no-audit --no-fund || true
                '''
            }
        }

        stage("Security Scans") {
            parallel {
                stage("OWASP Dependency Check") {
                    steps {
                        script {
                            try {
                                sh "mkdir -p $ODC_CACHE"
                                dependencyCheck additionalArguments: """
                                  --scan ./ 
                                  --disableYarnAudit 
                                  --disableNodeAudit 
                                  --data $ODC_CACHE
                                  --nvdApiKey=${NVD_API_KEY}
                                """,
                                odcInstallation: 'dp-check'

                                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
                            } catch (err) {
                                currentBuild.result = 'UNSTABLE'
                                echo "OWASP Dependency-Check failed or found vulnerabilities, marking build UNSTABLE"
                            }
                        }
                    }
                }

                stage("Trivy File Scan") {
                    steps {
                        script {
                            try {
                                sh '''
                                  mkdir -p $TRIVY_CACHE
                                  trivy --cache-dir $TRIVY_CACHE --download-db-only || true
                                  trivy fs --cache-dir $TRIVY_CACHE --skip-db-update --severity HIGH,CRITICAL . > trivyfs.txt || true
                                '''
                            } catch (err) {
                                currentBuild.result = 'UNSTABLE'
                                echo "Trivy FS scan failed or found vulnerabilities, marking build UNSTABLE"
                            }
                        }
                    }
                }
            }
        }

        stage("Docker Build, Push & Image Scan") {
            parallel {
                stage("Build & Push Docker Image") {
                    steps {
                        script {
                            env.IMAGE_TAG = "${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER}"
                            withCredentials([string(credentialsId: 'docker-cred', variable: 'dockerpwd')]) {
                                sh """
                                  # Build image with cache
                                  docker build \
                                    --cache-from=${DOCKER_USER}/${IMAGE_NAME}:latest \
                                    -t ${IMAGE_NAME} \
                                    -t ${env.IMAGE_TAG} .

                                  # Login and push
                                  echo $dockerpwd | docker login -u ${DOCKER_USER} --password-stdin
                                  docker push ${env.IMAGE_TAG}
                                  docker tag ${IMAGE_NAME} ${DOCKER_USER}/${IMAGE_NAME}:latest
                                  docker push ${DOCKER_USER}/${IMAGE_NAME}:latest
                                """
                            }
                        }
                    }
                }

                stage("Trivy Image Scan") {
                    steps {
                        script {
                            try {
                                sh """
                                  mkdir -p $TRIVY_CACHE
                                  trivy --cache-dir $TRIVY_CACHE --download-db-only || true

                                  echo '🔍 Running Trivy scan on ${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER}'
                                  trivy image --cache-dir $TRIVY_CACHE --skip-db-update --severity HIGH,CRITICAL -f json -o trivy-image.json ${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER} || true
                                  trivy image --cache-dir $TRIVY_CACHE --skip-db-update --severity HIGH,CRITICAL -f table -o trivy-image.txt ${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER} || true
                                """
                            } catch (err) {
                                currentBuild.result = 'UNSTABLE'
                                echo "Trivy image scan failed or found vulnerabilities, marking build UNSTABLE"
                            }
                        }
                    }
                }
            }
        }

        stage("Deploy Container") {
            steps {
                sh """
                  docker rm -f ${IMAGE_NAME} || true
                  docker run -d --name ${IMAGE_NAME} -p 80:80 ${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER} || true
                """
            }
        }
    }

    post {
        always {
            script {
                def buildStatus = currentBuild.currentResult
                def buildUser = currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause')[0]?.userId ?: 'GitHub User'

                // Archive reports
                archiveArtifacts artifacts: 'trivyfs.txt,trivy-image.json,trivy-image.txt,dependency-check-report.xml', allowEmptyArchive: true

                emailext (
                    subject: "Pipeline ${buildStatus}: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                    body: """
                        <p>Jenkins Amazon CICD Pipeline Status</p>
                        <p><b>Project:</b> ${env.JOB_NAME}</p>
                        <p><b>Build Number:</b> ${env.BUILD_NUMBER}</p>
                        <p><b>Status:</b> ${buildStatus}</p>
                        <p><b>Started by:</b> ${buildUser}</p>
                        <p><b>URL:</b> <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
                    """,
                    to: 'kishordpatil2107@gmail.com',
                    from: 'kishorpatil2107@gmail.com',
                    mimeType: 'text/html',
                    attachmentsPattern: 'trivyfs.txt,trivy-image.json,trivy-image.txt,dependency-check-report.xml'
                )
            }
        }
    }
}
