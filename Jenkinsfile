pipeline {
    agent any 
    options {
      timeout(time: 1, unit: 'HOURS') 
      buildDiscarder(logRotator(numToKeepStr: '3', artifactNumToKeepStr: '2', daysToKeepStr: '30'))
      timestamps()
    }
    parameters {
      string(name: 'branch_specifier', defaultValue: "refs/heads/master", description: "the Git branch specifier to build (<branchName>, <tagName>, <commitId>, etc.)")
      booleanParam(name: 'windows_cI', defaultValue: false, description: 'Enable Windows CI')
      booleanParam(name: 'deploy', defaultValue: false, description: 'Enable deploy')
    }
    
    stages {
      
      /**
      Basic build on a linux environment.
      */
        stage('Build') { 
            agent { label 'linux' }
            environment {
              PATH = "${env.PATH}:${env.HOME}/go/bin/:${env.WORKSPACE}/bin"
              GOPATH = "${env.WORKSPACE}"
            }
            
            steps {
                ansiColor('xterm') {
                    sh "export"
                    echo "${PATH}:${HOME}/go/bin/:${WORKSPACE}/bin"
                    /*
                    script {
                    }*/
                    dir("${BASE_DIR}"){
                      deleteDir()
                      checkout([$class: 'GitSCM', branches: [[name: "${branch_specifier}"]], 
                        doGenerateSubmoduleConfigurations: false, 
                        extensions: [], 
                        submoduleCfg: [], 
                        userRemoteConfigs: [[credentialsId: "${GIT_CREDENTIALS}", 
                        url: "${GIT_REPO_URL}"]]])
                      stash allowEmpty: true, name: 'source'
                      sh """
                      pwd
                      make
                      make update
                      """
                    }
                }
            }
        }
        
        /**
        Build and run tests on a linux environment.
        Finally archive the results.
        */
        stage('CI-linux') { 
            agent { label 'linux' }
            
            steps {
              ansiColor('xterm') {
                  dir("${BASE_DIR}"){  
                    deleteDir()
                    unstash 'source'
                    sh """
                    #!runbld 
                    ./script/jenkins/ci.sh
                    """
                  }
                }
              }
              post { 
                always {
                  googleStorageUpload bucket: "gs://${GCS_BUCKET}/${JOB_NAME}/${BUILD_NUMBER}", credentialsId: "${GCS_CREDENTIALS}", pathPrefix: "${BASE_DIR}", pattern: '**/build/system-tests/run/**/*', sharedPublicly: true, showInline: true
                  googleStorageUpload bucket: "gs://${GCS_BUCKET}/${JOB_NAME}/${BUILD_NUMBER}", credentialsId: "${GCS_CREDENTIALS}", pathPrefix: "${BASE_DIR}", pattern: '**/build/TEST-*.out', sharedPublicly: true, showInline: true
                  junit allowEmptyResults: true, keepLongStdio: true, testResults: "${BASE_DIR}/**/build/TEST-*.xml"
                }
              }
        }
        
        /**
        Build and run tests on a windows environment.
        Finally archive the results.
        */
        stage('CI-windows') { 
            agent { label 'windows' }
            
            when { 
              beforeAgent true
              environment name: 'windows_ci', value: 'true' 
            }
            steps {
              ansiColor('xterm') {
                  dir("${BASE_DIR}"){  
                    deleteDir()
                    unstash 'source'
                    powershell '''java -jar "C:\\Program Files\\infra\\bin\\runbld" `
                      --program powershell.exe `
                      --args "-NonInteractive -ExecutionPolicy ByPass -File" `
                      ".\\src\\github.com\\elastic\\apm-server\\script\\jenkins\\ci.ps1"'''
                  }
                }
              }
              post { 
                always {
                  googleStorageUpload bucket: "gs://${GCS_BUCKET}/${JOB_NAME}/${BUILD_NUMBER}", credentialsId: "${GCS_CREDENTIALS}", pathPrefix: "${BASE_DIR}", pattern: '**/build/system-tests/run/**/*', sharedPublicly: true, showInline: true
                  googleStorageUpload bucket: "gs://${GCS_BUCKET}/${JOB_NAME}/${BUILD_NUMBER}", credentialsId: "${GCS_CREDENTIALS}", pathPrefix: "${BASE_DIR}", pattern: '**/build/TEST-*.out', sharedPublicly: true, showInline: true
                  junit allowEmptyResults: true, keepLongStdio: true, testResults: "${BASE_DIR}/**/build/TEST-*.xml"
                }
              }
        }
        
        stage('Parallel Stage'){
          failFast false
            parallel {
              
              /**
              Runs unit test, then generate coverage and unit test reports.
              Finally archive the results.
              */
              stage('Test') { 
                  agent { label 'linux' }
                  environment {
                    PATH = "${env.PATH}:${env.HOME}/go/bin/:${env.WORKSPACE}/bin"
                    GOPATH = "${env.WORKSPACE}"
                  }
                  
                  steps {
                    ansiColor('xterm') {
                        dir("${BASE_DIR}"){
                          deleteDir()
                          unstash 'source'
                          sh """
                          pwd
                          make
                          make testsuite
                          
                          export GOPACKAGES=\$(go list github.com/elastic/apm-server/...| grep -v /vendor/ | grep -v /scripts/cmd/)
                          go get -u github.com/jstemmer/go-junit-report
                          go test -race \${GOPACKAGES} -v 2>&1 | go-junit-report > build/TEST-report.xml
                          
                          make coverage-report
                          """
                        }
                      }
                    }
                    post { 
                      always { 
                        publishHTML(target: [
                          allowMissing: true, 
                          keepAll: true,
                          reportDir: "${BASE_DIR}/build/coverage", 
                          reportFiles: 'full.html', 
                          reportName: 'coverage', 
                          reportTitles: 'Coverage'])
                        archiveArtifacts(allowEmptyArchive: true, 
                          artifacts: "${BASE_DIR}/build/coverage/**/*,${BASE_DIR}/build/system-tests/**/*,${BASE_DIR}/build/TEST-*.out,${BASE_DIR}/build/TEST-*.xml", 
                          onlyIfSuccessful: false)
                        junit(allowEmptyResults: true, 
                          keepLongStdio: true, 
                          testResults: "${BASE_DIR}/build/**/TEST-*.xml")
                      }
                    }
              }
              
              /**
              Runs benchmarks on the current version and compare it with the previous ones.
              Finally archive the results.
              */
              stage('Benchmarking') {
                  agent { label 'linux' }
                  environment {
                    PATH = "${env.PATH}:${env.HOME}/go/bin/:${env.WORKSPACE}/bin"
                    GOPATH = "${env.WORKSPACE}"
                  }
                  
                  steps {
                    ansiColor('xterm') {
                        dir("${BASE_DIR}"){  
                          deleteDir()
                          unstash 'source'
                          copyArtifacts filter: 'bench-last.txt', fingerprintArtifacts: true, optional: true, projectName: "${JOB_NAME}", selector: lastCompleted()
                          sh """
                          pwd
                          go get -u golang.org/x/tools/cmd/benchcmp
                          make bench > new.txt
                          [ -f bench-last.txt ] && benchcmp bench-last.txt new.txt > bench-diff.txt 
                          [ -f bench-last.txt ] && mv bench-last.txt bench-old.txt
                          mv new.txt bench-last.txt
                          [ -f bench-diff.txt ] && cat bench-diff.txt
                          """
                          archiveArtifacts allowEmptyArchive: true, artifacts: "bench-last.txt", onlyIfSuccessful: false
                          archiveArtifacts allowEmptyArchive: true, artifacts: "bench-old.txt", onlyIfSuccessful: false
                          archiveArtifacts allowEmptyArchive: true, artifacts: "bench-diff.txt", onlyIfSuccessful: false
                        }
                      }
                    }
              }
              
              /**
              updates beats updates the framework part and go parts of beats. 
              Then build and test.
              Finally archive the results.
              */
              /*
              stage('Update Beats') { 
                  agent { label 'linux' }
                  
                  steps {
                    ansiColor('xterm') {
                        dir("${BASE_DIR}"){
                          deleteDir()
                          unstash 'source'
                          sh """
                          #!runbld
                          ./script/jenkins/update-beats.sh
                          """
                          archiveArtifacts allowEmptyArchive: true, artifacts: "${BASE_DIR}/build", onlyIfSuccessful: false
                        }
                      }
                    }
              }*/
              
              /**
              Updating generated files for Beat.
              Checks the GO environment.
              Checks the Python environment.
              Checks YAML files are generated. 
              Validate that all updates were committed.
              */
              /*
              stage('Intake') { 
                  agent { label 'linux' }
                  
                  steps {
                    ansiColor('xterm') {
                        dir("${BASE_DIR}"){  
                          deleteDir()
                          unstash 'source'
                          sh """
                          #!runbld
                          ./script/jenkins/intake.sh
                          """
                        }
                      }
                    }
              }*/
              
              /**
              Build the documentation and archive it.
              Finally archive the results.
              */
              stage('Documentation') { 
                  agent { label 'linux' }
                  environment {
                    PATH = "${env.PATH}:${env.HOME}/go/bin/:${env.WORKSPACE}/bin"
                    GOPATH = "${env.WORKSPACE}"
                  }
                  
                  steps {
                    ansiColor('xterm') {
                        dir("${BASE_DIR}"){  
                          deleteDir()
                          unstash 'source'
                          sh """
                          #!runbld
                          make docs
                          """
                        }
                      }
                    }
                    post{
                      always {
                        archiveArtifacts allowEmptyArchive: true, artifacts: "${BASE_DIR}/build/html_docs/**/*", onlyIfSuccessful: false
                      }
                    }
              }
              
              /**
              Checks if kibana objects are updated.
              */
              /*
              stage('Check kibana Obj. Updated') { 
                  agent { label 'linux' }
                  
                  steps {
                    ansiColor('xterm') {
                        dir("${BASE_DIR}"){  
                          deleteDir()
                          unstash 'source'
                          sh """
                          #!runbld
                          ./script/jenkins/sync.sh
                          """
                        }
                      }
                    }
              }*/
            }
        }
        
        /**
        TODO eploy binaries 
        */
        stage('Deploy') { 
            agent { label 'linux' }
            
            when { 
              beforeAgent true
              environment name: 'deploy', value: 'true' 
            }
            steps {
              nsiColor('xterm') {
                dir("${BASE_DIR}"){
                  deleteDir()
                  unstash 'source'
                  echo "NOOP"
                }
              }  
            }
        }
    }
    post { 
      success { 
          echo 'Success Post Actions'
      }
      aborted { 
          echo 'Aborted Post Actions'
      }
      failure { 
          echo 'Failure Post Actions'
          //step([$class: 'Mailer', notifyEveryUnstableBuild: true, recipients: "${NOTIFY_TO}", sendToIndividuals: false])
      }
      unstable { 
          echo 'Unstable Post Actions'
      }
      always { 
          echo 'Post Actions'
      }
    }
}