
def withDockerNetwork(Closure inner) {
    try {
        networkId = UUID.randomUUID().toString()
        sh "docker network create ${networkId}"
        inner.call(networkId)
    } finally {
        sh "docker network rm ${networkId}"
    }
}

def getTaskDefinition(imageTag, cpu, memory, profile, elasticsearchDest, configServerServiceId, eurekaUrl, sentryDsn) {
    return groovy.json.JsonOutput.toJson([
       "executionRoleArn": env.AWS_ROLE_ARN,
       "taskRoleArn": env.AWS_ROLE_ARN,
       "networkMode": "bridge",
       "containerDefinitions": [
           [
               "image": env.AWS_ECR_HOST + '/' + env.IMAGE_NAME + ':' + imageTag,
               "name": env.IMAGE_NAME,
               "essential": true,
               "logConfiguration": ["logDriver":"json-file"],
               "cpu": cpu,
               "memory": memory,
               "environment": [
                   ["name": "APP_NAME", "value": env.IMAGE_NAME],
                   ["name": "APP_PORT", "value": "80"],
                   ["name": "SPRING_PROFILES_ACTIVE", "value": profile],
                   ["name": "APP_LOG_LEVEL", "value": "ERROR"],
                   ["name": "ELASTICSEARCH_LOG_PRE", "value": elasticsearchDest],
                   ["name": "CONFIG_SERVER_SERVICE_ID", "value": configServerServiceId],
                   ["name": "EUREKA_URL", "value": eurekaUrl],
                   ["name": "SENTRY_DSN", "value": sentryDsn],
                   ["name": "SENTRY_SERVERNAME", "value": env.IMAGE_NAME],
                   ["name": "SENTRY_RELEASE", "value": env.IMAGE_VERSION],
                   ["name": "SENTRY_ENVIRONMENT", "value": profile],
                   ["name": "SENTRY_SAMPLE_RATE", "value": "1"]
               ]
              , "portMappings": [
                ["hostPort": 0, "containerPort": 80]
              ]
              , "healthCheck": [
                "command": [ "CMD-SHELL", /if [ $(curl http:\/\/localhost:80\/actuator\/health | grep -oP '(?<="status":")[^"]*' | sed -n 1p) != "UP" ]; then exit 1; fi/ ],
                "interval": 5,
                "retries": 2,
                "startPeriod": 90,
                "timeout": 2
              ]
           ]
       ]
   ])
}

def getServiceDefinition(cluster, taskName) {
    return [
        "cluster": cluster,
        "taskDefinition": taskName,
        "desiredCount": 1,
        "deploymentConfiguration": [
            "maximumPercent": 100,
            "minimumHealthyPercent": 0
        ]
    ]
}

pipeline {
    agent any

    environment {
        IMAGE_NAME = "Symfony7"
        IMAGE_VERSION = "1.0"
    }

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '10'))
    }

    stages {

        stage('build docker') {
            steps {
                sh './dkbuild.sh' 
            }
        }

        stage('Ejecutar Symfony Composer Install') {
            steps {
                script {
                     docker.image("Symfony7").inside("--network=host") {
                        sh "docker exec symfony7 sh -c 'cd $WORKSPACE && composer install'"
                    }
                }
            }
        }
        
        /*stage('Build') {
            steps {
                script {
                    withDockerNetwork { n ->
                        docker.image("${env.MAVEN_IMAGE}").inside("--network ${n} -v /var/run/docker.sock:/var/run/docker.sock") {
                            configFileProvider([configFile(fileId: 'cf3ab86d-2cf1-416d-84a4-cce3552e3c6e', variable: 'MAVEN_SETTINGS_XML')]) {
                                sh 'mvn -s $MAVEN_SETTINGS_XML clean package -U'
                            }
                            stash includes: 'target/*.jar', name: 'targetFiles'
                        }
                    }
                }
            }
        }

        stage('build image') {
            when {
                anyOf {
                    branch 'master'
                    branch 'develop'
                }
            }
            steps {
                unstash 'targetFiles'
                script {
                    dockerImage = docker.build("${env.AWS_ECR_HOST}/${env.IMAGE_NAME}", ".")
                }
            }
        }

        stage('publish image develop') {
            when {
                branch 'develop'
            }
            steps {
                script {
                    docker.withRegistry("https://${env.AWS_ECR_HOST}","ecr:"+ env.AWS_ZONE +":linkener-deployment-aws") {
                        dockerImage.push("develop")
                    }
                }
            }
        }

        stage('publish image master') {
            when {
                branch 'master'
            }
            steps {
                script {
                    docker.withRegistry("https://${env.AWS_ECR_HOST}","ecr:"+ env.AWS_ZONE +":linkener-deployment-aws") {
                        dockerImage.push("master")
                        dockerImage.push("${env.IMAGE_VERSION}")
                    }
                }
            }
        }

        stage('ECS deployment') {
            when {
                anyOf {
                    branch 'master'
                    branch 'develop'
                }
            }
            steps {
                script {
                    withAWS(credentials:'linkener-deployment-aws', region: env.AWS_ZONE) {
                        if (env.BRANCH_NAME == "develop") {
                            cluster = "Linkener-PRE"
                            taskName = "${env.IMAGE_NAME}-pre-task"
                            taskDefinition = getTaskDefinition(
                                "develop",
                                0, 1024,
                                "stage",
                                env.ELASTICSEARCH_HOST_PRE,
                                "config-server",
                                env.EUREKA_SERVER_URL_PRE,
                                env.SENTRY_DSN_PRE
                            )
                        } else if(env.BRANCH_NAME == "master") {
                            cluster = "Linkener-PROD"
                            taskName = "${env.IMAGE_NAME}-prod-task"
                            taskDefinition = getTaskDefinition(
                                env.IMAGE_VERSION,
                                0, 1024,
                                "prod",
                                env.ELASTICSEARCH_HOST_PROD,
                                "config-server",
                                env.EUREKA_SERVER_URL_PROD,
                                env.SENTRY_DSN_PROD
                            )
                        } else {
                            error("Invalid branch in ECS deployment task")
                        }

                        // create task definition
                        writeFile file: "${WORKSPACE}/task-definition.json", text: taskDefinition, encoding: 'UTF-8'
                        sh "aws ecs register-task-definition --family ${taskName} --cli-input-json file://${WORKSPACE}/task-definition.json"

                        // handle ECS service
                        result = sh (script: "aws ecs describe-services --services ${env.IMAGE_NAME} --cluster=$cluster", returnStdout: true)
                        serviceStatus = readJSON(text: result)
                        serviceDefinition = getServiceDefinition(cluster, taskName)

                        // service does not exists or was disabled
                        if(serviceStatus.services.size() == 0 || (serviceStatus.services.size() == 1 && serviceStatus.services[0].status != 'ACTIVE')) {
                            serviceDefinition["serviceName"] = env.IMAGE_NAME
                            writeFile file: "${WORKSPACE}/service-definition.json", text: groovy.json.JsonOutput.toJson(serviceDefinition), encoding: 'UTF-8'
                            sh "aws ecs create-service --cli-input-json file://${WORKSPACE}/service-definition.json"
                        } else {
                            serviceDefinition["service"] = env.IMAGE_NAME
                            writeFile file: "${WORKSPACE}/service-definition.json", text: groovy.json.JsonOutput.toJson(serviceDefinition), encoding: 'UTF-8'
                            sh "aws ecs update-service --cli-input-json file://${WORKSPACE}/service-definition.json"
                        }
                    }
                }
            }
        }*/

    }

    post {
        always {
            echo 'Finished, cleaning up workspace...'
            deleteDir() /* clean up our workspace */
        }
    }

}
