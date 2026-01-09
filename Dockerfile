FROM m.daocloud.io/docker.io/maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -q -DskipTests package

FROM m.daocloud.io/docker.io/eclipse-temurin:21-jre
RUN adduser --system --group appuser
WORKDIR /app
ARG APP_VERSION=unknown
ARG GIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION}
ENV GIT_SHA=${GIT_SHA}
COPY --from=build --chown=appuser:appuser /workspace/target/*.jar /app/app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
