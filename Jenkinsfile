pipeline {
  agent any
  stages {
    stage('one') {
      parallel {
        stage('one') {
          steps {
            sh 'export'
          }
        }
        stage('two') {
          steps {
            echo 'hello!!!'
            node(label: 'linux') {
              sh 'echo hello'
            }

          }
        }
      }
    }
  }
  environment {
    Home = '/home'
  }
}