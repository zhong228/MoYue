plugins {
    kotlin("jvm") version "2.0.21"
    application
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(kotlin("stdlib"))
    implementation("org.jsoup:jsoup:1.16.2")
    implementation("cn.wanghaomiao:JsoupXpath:2.5.3")
}

application {
    mainClass.set("io.legado.app.model.analyzeRule.CompareMainKt")
}

kotlin {
    jvmToolchain(17)
}
