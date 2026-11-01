FROM maven:3.8.8-eclipse-temurin-8@sha256:daa5d635ffdeb1a3c31d12079b6829115214701828e43d61e4e7f6a61640e62c AS build
WORKDIR /source
COPY server/pom.xml ./pom.xml
COPY server/src ./src
RUN mvn -B -Pprod clean package -DskipTests

FROM eclipse-temurin:8-jre@sha256:377fe8e36a4b1530d9d52020069367ef44313fa891a82ae102b1016a6a3a72f5
WORKDIR /app
RUN groupadd --system opendine && useradd --system --gid opendine opendine \
    && mkdir -p /var/lib/opendine/public/qrcode /var/lib/opendine/public/dish \
       /var/lib/opendine/public/avatar /var/lib/opendine/public/advertising \
       /var/lib/opendine/public/images /var/lib/opendine/public/offline-collect \
       /var/lib/opendine/public/packages /var/lib/opendine/public/poster/bg \
       /var/lib/opendine/private/payment-keys \
    && chown -R opendine:opendine /var/lib/opendine
COPY --from=build /source/target/diancan-0.0.1-SNAPSHOT.jar /app/app.jar
COPY deploy/application-deploy.yml /app/deployment.yml
COPY deploy/sql/init.sql /bootstrap/deploy/sql/init.sql
COPY server/docs/db_migration_rbac_v2.sql server/docs/db_migration_api_permission_full.sql /bootstrap/server/docs/
COPY server/docs/db_migration_kds_projection_intent.sql server/docs/db_migration_kds_shared_revision.sql server/docs/db_migration_report_job_recovery.sql /bootstrap/server/docs/
COPY server/docs/db_migration_shop_settle_flow.sql /bootstrap/server/docs/
USER opendine
EXPOSE 8080
ENTRYPOINT ["java", "-Dfile.encoding=UTF-8", "-jar", "/app/app.jar"]
