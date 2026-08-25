<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="{{ repo_url }}/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>{{ text_plugin_synopsis }}</p>

  <p>
    <a href="{{ repo_url }}/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/{{ repo_slug }}?label=Release"/></a>
    <a href="{{ repo_url }}/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/{{ repo_slug }}?color=A24232&label=Issues"/></a>
    <a href="{{ repo_url }}/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/{{ repo_slug }}?color=534BAE&label=License"/></a>
  </p>
</div>

******

### {{ h3_languages_with_ascii }}

******

{{ p_languages_all_supported_for_readme }}:

{{ placeholder_ul_languages_all_supported }}

******

### {{ h3_introduction }}

******

{{ p_introduction }}

******

### {{ h3_how_it_works }}

******

{{ p_how_it_works }}:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

{{ p_how_it_works_note }}

******

### {{ h3_functions }}

******

{{ placeholder_features }}

******

### {{ h3_user_guide }}

******

{{ p_user_guide_overview }}

#### {{ h4_user_guide_prerequisites }}

{{ p_user_guide_prerequisites }}

```text
host package: {{ host_package }}
plugin package: {{ plugin_package }}
minimum host build: {{ required_host_build }}
exact component: {{ exact_service_component }}
```

#### {{ h4_user_guide_install_enable }}

{{ p_user_guide_install_enable }}

#### {{ h4_user_guide_status }}

{{ p_user_guide_status }}

#### {{ h4_user_guide_example }}

{{ p_user_guide_example }}

```javascript
"use strict";

const jar = files.path("./lib/example.jar");
if (!files.isFile(jar)) {
    throw new Error("Missing JAR: " + jar);
}

runtime.loadJar(jar);

// Replace this with a public class that actually exists in example.jar.
const Example = Packages.com.example.autojs6.DexPluginExample;
console.log("DEX compiler example: " + Example.answer());
```

{{ p_user_guide_example_note }}

#### {{ h4_user_guide_fallback }}

{{ p_user_guide_fallback }}

#### {{ h4_user_guide_troubleshooting }}

{{ p_user_guide_troubleshooting }}

```powershell
adb -s <serial> shell dumpsys package {{ host_package }}
adb -s <serial> shell dumpsys package {{ plugin_package }}
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### {{ h4_user_guide_disable_uninstall }}

{{ p_user_guide_disable_uninstall }}

******

### {{ h3_faq }}

******

{{ p_faq }}

******

### {{ h3_boundaries }}

******

{{ p_boundaries_intro }}:

{{ placeholder_boundaries }}

******

### {{ h3_reference }}

******

{{ p_reference_intro }}

#### {{ h4_reference_formats }}

{{ p_formats }}:

```text
input: {{ input_format }}
output: {{ output_format }}
compiler: {{ compiler_dependency }}
```

#### {{ h4_reference_interface }}

{{ p_plugin_interface }}:

```text
service action: {{ plugin_action }}
plugin id: {{ plugin_id }}
protocol provider id: {{ protocol_provider_id }}
engine: {{ plugin_engine }}
variant: {{ plugin_variant }}
protocol: {{ protocol_version }}
required host build: {{ required_host_build }}
```

{{ p_plugin_scope }}

{{ p_plugin_packaging }}

#### {{ h4_reference_security }}

{{ p_security }}

#### {{ h4_reference_limits }}

{{ p_reference_limits_intro }}:

{{ placeholder_security_limits }}

#### {{ h4_reference_caveats }}

{{ placeholder_caveats }}

******

### {{ h3_roadmap }}

******

{{ p_roadmap_status }}

- [{{ text_open_roadmap }}]({{ repo_url }}/blob/master/ROADMAP.md)

******

### {{ h3_release_history }}

******

{{ placeholder_latest_release_history }}

##### {{ h5_for_more_release_history }}

* {{ placeholder_read_more_in_changelog_md }}

******

### {{ h3_build }}

******

```powershell
.\gradlew.bat :app:assembleDebug
```

{{ text_release_build }}:

```powershell
.\gradlew.bat :app:assembleRelease
```

{{ p_build_params }}.

{{ p_local_aars }}:

```text
{{ local_aars }}
```

{{ p_build_architecture }}

******

### {{ h3_license }}

******

{{ p_license }}

******

### {{ h3_resource_layout }}

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

{{ p_resource_layout }}.

******

### {{ h3_links }}

******

- {{ text_link_autojs6_docs }}: {{ docs_autojs6_url }}
- {{ text_link_upstream }}: {{ upstream_url }}
