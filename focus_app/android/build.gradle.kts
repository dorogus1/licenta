allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        project.extensions.findByName("android")?.let { android ->
            try {
                // FORCE COMPILE SDK VERSION TO 36
                val setCompileSdkVersion = android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                setCompileSdkVersion.invoke(android, 36)
            } catch (e: Exception) {
                // println("Failed to set compileSdk for ${project.name}: $e")
            }

            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(android) == null) {
                    var packageName: String? = null
                    
                    // 1. Try Manifest
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                         val content = manifestFile.readText()
                         val match = Regex("package=\"([^\"]*)\"").find(content)
                         if (match != null) {
                             packageName = match.groupValues[1]
                         }
                    }
                    
                    // 2. Try Java Source (if manifest failed or attribute already removed)
                    if (packageName == null) {
                        val javaDir = file("src/main/java")
                        if (javaDir.exists()) {
                            val firstJavaFile = javaDir.walkTopDown().filter { it.extension == "java" }.firstOrNull()
                            if (firstJavaFile != null) {
                                firstJavaFile.useLines { lines ->
                                    for (line in lines) {
                                        if (line.trim().startsWith("package ")) {
                                            packageName = line.trim().substringAfter("package ").substringBefore(";").trim()
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (packageName == null) {
                         packageName = "com.example.${project.name.replace("-", "_")}"
                    }

                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, packageName)
                    println("Set namespace for ${project.name} to $packageName")
                }
            } catch (e: Exception) {
                // Ignore
            }
        }
        
        // Fix for "Incorrect package found in source AndroidManifest.xml"
        if (project.hasProperty("android")) {
            val removePackageAttribute = tasks.register("removePackageAttribute") {
                doLast {
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val content = manifestFile.readText()
                        if (content.contains("package=\"")) {
                            val updatedContent = content.replace(Regex("package=\"[^\"]*\""), "")
                            manifestFile.writeText(updatedContent)
                            println("Removed package attribute from ${manifestFile.path}")
                        }
                    }
                }
            }
            tasks.matching { it.name.contains("process") && it.name.contains("Manifest") }.configureEach {
                dependsOn(removePackageAttribute)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
