pipeline {
    agent any

    tools {
        jdk 'jdk17'
        nodejs 'node16'
    }

    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        IMAGE_NAME   = "amazon"
        DOCKER_USER  = "harishnshetty"
        SONAR_PROJECT = "amazon"
        NVD_API_KEY = credentials('nvd-api-key')   // Add in Jenkins Credentials
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
                  npm ci --prefer-offline --no-audit --no-fund
                '''
            }
        }

        stage("Security Scans") {
            parallel {
                stage("OWASP Dependency Check") {
                    steps {
                        dependencyCheck additionalArguments: """
                          --scan ./ 
                          --disableYarnAudit 
                          --disableNodeAudit 
                          --nvdApiKey=${NVD_API_KEY}
                        """,
                        odcInstallation: 'dp-check'

                        dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
                    }
                }

                stage("Trivy File Scan") {
                    steps {
                        sh '''
                          trivy fs --skip-update --severity HIGH,CRITICAL . > trivyfs.txt
                        '''
                    }
                }

                stage("Trivy Image Scan (Pre-Build)") {
                    steps {
                        sh "trivy --download-db-only || true"
                    }
                }
            }
        }

        stage("Build Docker Image") {
            steps {
                script {
                    env.IMAGE_TAG = "${DOCKER_USER}/${IMAGE_NAME}:${BUILD_NUMBER}"

                    sh """
                      docker build \
                        --cache-from=${DOCKER_USER}/${IMAGE_NAME}:latest \
                        -t ${IMAGE_NAME} \
                        -t ${env.IMAGE_TAG} .
                    """
                }
            }
        }

        stage("Push Docker Image") {
            steps {
                script {
                    withCredentials([string(credentialsId: 'docker-cred', variable: 'dockerpwd')]) {
                        sh """
                          echo $dockerpwd | docker login -u ${DOCKER_USER} --password-stdin
                          docker push ${env.IMAGE_TAG}
                          docker tag ${IMAGE_NAME} ${DOCKER_USER}/${IMAGE_NAME}:latest
                          docker push ${DOCKER_USER}/${IMAGE_NAME}:latest
                        """
                    }
                }
            }
        }

        stage("Trivy Scan Image (Post-Push)") {
            steps {
                script {
                    sh """
                      echo '🔍 Running Trivy scan on ${env.IMAGE_TAG}'
                      trivy image --skip-update --severity HIGH,CRITICAL -f json -o trivy-image.json ${env.IMAGE_TAG}
                      trivy image --skip-update --severity HIGH,CRITICAL -f table -o trivy-image.txt ${env.IMAGE_TAG}
                    """
                }
            }
        }

        stage("Deploy Container") {
            steps {
                sh """
                  docker rm -f ${IMAGE_NAME} || true
                  docker run -d --name ${IMAGE_NAME} -p 80:80 ${env.IMAGE_TAG}
                """
            }
        }
    }

    post {
        always {
            script {
                def buildStatus = currentBuild.currentResult
                def buildUser = currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause')[0]?.userId ?: 'GitHub User'

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
