FROM eclipse-temurin:25-jre-alpine
COPY target/payment-paypal-1.0-SNAPSHOT.jar app.jar

# SỬA DÒNG ENTRYPOINT THÀNH DÒNG DƯỚI ĐÂY:
# Ép chạy thông qua Classpath Loader của Spring để không cần thuộc tính Main-Class trong Manifest
ENTRYPOINT ["java", "-cp", "app.jar", "org.springframework.boot.loader.launch.JarLauncher"] 