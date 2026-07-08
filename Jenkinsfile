pipeline {
    agent any

    environment {
        // TODO: Đổi thành account Docker Hub của nhóm bạn
        DOCKERHUB_ACCOUNT = 'tuandaklak' 
    }

    tools {
        jdk 'jdk25'
        maven 'maven3'
    }

    stages {
        stage('Build Common Library') {
            steps {
                echo 'Đang Build Common Library...'
                sh 'mvn clean install -pl common-library -am'
            }
        }

        stage('Build & Test All Services') {
            steps {
                script {
                    // Đọc file pom.xml dưới dạng văn bản thuần để tránh lỗi Jenkins Sandbox (RejectedAccessException)
                    def pomText = readFile('pom.xml')
                    def services = []
                    def lines = pomText.split('\n')
                    for (int j = 0; j < lines.length; j++) {
                        def line = lines[j].trim()
                        if (line.startsWith('<module>') && line.endsWith('</module>')) {
                            def moduleName = line.substring(8, line.length() - 9)
                            if (moduleName != 'common-library' && moduleName != 'payment-paypal') {
                                services.add(moduleName)
                            }
                        }
                    }

                    // 1. Lấy danh sách toàn bộ các file có thay đổi (Giải quyết Rủi ro số 3)
                    def changedFiles = []
                    
                    try {
                        if (env.CHANGE_TARGET) {
                            sh "git fetch --no-tags origin ${env.CHANGE_TARGET}:refs/remotes/origin/${env.CHANGE_TARGET} || true"
                            
                            // Nếu là Pull Request, so sánh độ lệch với nhánh đích
                            def diffStr = sh(script: "git diff --name-only origin/${env.CHANGE_TARGET}...HEAD", returnStdout: true).trim()
                            if (diffStr) changedFiles.addAll(diffStr.split('\n'))
                        } else {
                            // Chạy trên nhánh trực tiếp (main hoặc feature branch), lấy file thay đổi của commit đó
                            sh "git fetch --unshallow || git fetch --depth=50 origin HEAD || true"
                            def diffStr = sh(script: "git diff --name-only HEAD~1 HEAD", returnStdout: true).trim()
                            if (diffStr) changedFiles.addAll(diffStr.split('\n'))
                        }
                    } catch (Exception e) {
                        echo "Warning: git diff thất bại, hệ thống sẽ sử dụng Jenkins changeSets làm phương án dự phòng."
                    }

                    // Lấy dữ liệu an toàn thông qua hàm @NonCPS để tránh lỗi NotSerializableException
                    changedFiles.addAll(extractChangedFiles())
                    
                    // Hàm kiểm tra cuối cùng (Không tự động chạy tất cả nếu rỗng)
                    def checkChanges = { serviceName ->
                        if (env.FORCE_BUILD_ALL == 'true') return true
                        return changedFiles.any { path ->
                            path.startsWith("${serviceName}/") || path.startsWith("common-library/")
                        }
                    }

                    // Lưu lại danh sách service có thay đổi để dùng cho stage Build & Push Image
                    def changedServicesList = []

                    // Khởi tạo danh sách các stage song song
                    def parallelStages = [:]

                    for (int i = 0; i < services.size(); i++) {
                        // Khai báo biến cục bộ để tránh lỗi scope closure trong Groovy
                        def serviceName = services[i]

                        if (checkChanges(serviceName)) {
                            changedServicesList.add(serviceName)
                            parallelStages[serviceName] = {
                                stage("Build Phase - ${serviceName}") {
                                    echo "Đang Build service: ${serviceName}..."
                                    lock('maven-build') {
                                        sh "mvn install -pl ${serviceName} -am -DskipTests"
                                    }
                                }
                                
                                stage("Test Phase - ${serviceName}") {
                                    echo "Đang Test và Đo lường độ phủ cho service: ${serviceName}..."
                                    lock('maven-build') {
                                        sh "mvn org.jacoco:jacoco-maven-plugin:prepare-agent test org.jacoco:jacoco-maven-plugin:report -pl ${serviceName} -Dserver.port=0 -Dspring.jmx.enabled=false" 
                                    }
                                    
                                    script {
                                        if (fileExists("${serviceName}/target/surefire-reports")) {
                                            junit allowEmptyResults: true, 
                                                  testResults: "${serviceName}/target/surefire-reports/*.xml"
                                        } else {
                                            echo "Bỏ qua JUnit vì không có test reports nào cho ${serviceName}"
                                        }

                                        if (fileExists("${serviceName}/target/jacoco.exec")) {
                                            jacoco(
                                                execPattern: "${serviceName}/target/jacoco.exec",
                                                classPattern: "${serviceName}/target/classes",
                                                sourcePattern: "${serviceName}/src/main/java",
                                                exclusionPattern: '**/config/**,**/exception/**,**/constants/**,**/*Application.class', 
                                                changeBuildStatus: true,
                                                minimumLineCoverage: '70', 
                                                maximumLineCoverage: '70'       
                                            )
                                        } else {
                                            echo "Bỏ qua kiểm tra độ phủ 70% trên Jenkins vì không có file execution data cho ${serviceName}"
                                        }
                                    }
                                }
                            }
                        } else {
                            echo "Bỏ qua ${serviceName} vì không có sự thay đổi mã nguồn."
                        }
                    }

                    // Gán vào biến môi trường để stage tiếp theo có thể đọc được
                    env.CHANGED_SERVICES = changedServicesList.join(',')

                    // Thực thi các stage (hiển thị giao diện Jenkins giống matrix)
                    if (parallelStages.size() > 0) {
                        parallel parallelStages
                    } else {
                        echo "Không có thay đổi nào trong các service, bỏ qua bước Build & Test."
                    }
                }
            }
        }

        stage('Build & Push Image') {
            when {
                // Chỉ chạy stage này nếu có ít nhất 1 service bị thay đổi
                expression { env.CHANGED_SERVICES != null && env.CHANGED_SERVICES != '' }
            }
            steps {
                script {
                    def commitId = sh(
                        script: 'git rev-parse HEAD | cut -c1-7',
                        returnStdout: true
                    ).trim()
                    env.COMMIT_ID = commitId

                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh "echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin"

                        env.CHANGED_SERVICES.split(',').each { svc ->
                            sh """
                                docker build -t ${env.DOCKERHUB_ACCOUNT}/${svc}:${commitId} ./${svc}
                                docker push ${env.DOCKERHUB_ACCOUNT}/${svc}:${commitId}
                            """
                            // Nếu là branch main → cũng push tag latest
                            if (env.BRANCH_NAME == 'main') {
                                sh """
                                    docker tag ${env.DOCKERHUB_ACCOUNT}/${svc}:${commitId} ${env.DOCKERHUB_ACCOUNT}/${svc}:latest
                                    docker push ${env.DOCKERHUB_ACCOUNT}/${svc}:latest
                                """
                            }
                        }
                    }
                    // Lưu lại commit id để TV3 (ArgoCD stage) sử dụng
                    sh "echo ${commitId} > build-info.txt"
                    archiveArtifacts artifacts: 'build-info.txt'
                }
            }
        }

        stage('Deploy to GitOps Branch') {
            when {
                branch 'main'
            }
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'github-token-new',
                        usernameVariable: 'GIT_USER',
                        passwordVariable: 'GIT_TOKEN'
                    )]) {
                        sh """
                            git config --global user.name "Jenkins GitOps"
                            git config --global user.email "jenkins@yas.local"
                            
                            # Cài đặt URL có nhúng token để push
                            git remote set-url origin https://\${GIT_USER}:\${GIT_TOKEN}@github.com/Nat90711/project-devops-yas.git
                            
                            # Xóa nhánh gitops cục bộ nếu có
                            git branch -D gitops || true
                            
                            # Tạo và chuyển thẳng sang nhánh gitops từ trạng thái Detached HEAD hiện tại
                            git checkout -b gitops
                            
                            # Đóng gói Helm dependencies cho các subcharts trước (product, order...)
                            for dir in k8s/charts/*/; do
                                if [ -f "\$dir/Chart.yaml" ] && [ "\$(basename \$dir)" != "yas-all" ]; then
                                    helm dependency build "\$dir"
                                fi
                            done
                            
                            # Đóng gói Helm dependency cho umbrella chart cuối cùng
                            helm dependency build k8s/charts/yas-all
                            
                            # Cập nhật imageTag cho các môi trường bằng COMMIT_ID mới nhất
                            sed -i 's/imageTag: .*/imageTag: "'\${env.COMMIT_ID}'"/g' k8s/environments/dev/values.yaml
                            sed -i 's/imageTag: .*/imageTag: "'\${env.COMMIT_ID}'"/g' k8s/environments/staging/values.yaml
                            
                            # Force add folder charts (phòng khi bị gitignore)
                            git add -f k8s/charts/yas-all/charts
                            
                            # Theo dõi các file values.yaml vừa sửa
                            git add k8s/environments/dev/values.yaml
                            git add k8s/environments/staging/values.yaml
                            
                            # Commit
                            git commit -m "chore: update gitops manifests [skip ci]" || true
                            
                            # Force push lên nhánh gitops
                            git push origin gitops -f
                        """
                    }
                }
            }
        }
    }
}

@NonCPS
def extractChangedFiles() {
    def files = []
    def changeLogSets = currentBuild.changeSets
    if (changeLogSets != null) {
        for (int i = 0; i < changeLogSets.size(); i++) {
            def entries = changeLogSets[i].items
            for (int j = 0; j < entries.length; j++) {
                def affectedFiles = entries[j].affectedFiles
                for (int k = 0; k < affectedFiles.size(); k++) {
                    files.add(affectedFiles[k].path)
                }
            }
        }
    }
    return files
}
