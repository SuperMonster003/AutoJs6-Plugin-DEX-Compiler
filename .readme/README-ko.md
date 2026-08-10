<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>독립 DEX 컴파일러 플러그인. 검증된 JAR을 D8로 연속된 classes*.dex ZIP으로 컴파일</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### 언어

******

현재 README.md는 다음 언어를 지원합니다:

- [简体中文 [zh-Hans]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hans.md)
- [繁體中文 (香港) [zh-Hant-HK]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-HK.md)
- [繁體中文 (台灣) [zh-Hant-TW]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-zh-Hant-TW.md)
- [English [en]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-en.md)
- [Français [fr]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-fr.md)
- [Español [es]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-es.md)
- [日本語 [ja]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ja.md)
- 한국어 [ko] # 현재
- [Русский [ru]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ru.md)
- [العربية [ar]](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/.readme/README-ar.md)

******

### 소개

******

DEX Compiler는 AutoJs6 DEX Compiler 프로토콜 V1을 위한 독립 provider입니다. 앱 전용 작업 공간에서 D8을 사용해 엄격히 검증한 JVM JAR을 컴파일하고 호스트가 제공한 출력 descriptor로 정규 DEX ZIP을 반환합니다.

******

### 기능

******

- DEBUG 또는 RELEASE 모드 JAR 입력, minApi 24부터 36 및 multi-dex 출력을 지원합니다.
- 컴파일 전에 선언한 크기와 SHA-256, ZIP framing, entry 이름, class magic, 중복 및 압축 해제 경계를 검증합니다.
- 외부 classpath를 받지 않고 기기 runtime boot classpath와 fingerprint를 기준으로 컴파일합니다.
- 연속된 `classes.dex`, `classes2.dex` 이후 DEX 파일만 패키징하고 실제 ZIP 크기와 SHA-256을 반환합니다.
- Android API 26 이상에서는 D8Command, API 24와 25에서는 D8 CLI fallback을 사용합니다.

******

### 입력 및 출력 형식

******

버전 1은 다음 컴파일 범위만 선언합니다:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.17
```

******

### 플러그인 인터페이스

******

호스트는 다음 식별자로 플러그인을 검색하고 호출합니다:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

플러그인은 D8 8.13.17, JAR 입력, DEX ZIP 출력, DEBUG 및 RELEASE 모드, minApi 24부터 36과 multi-dex를 선언합니다. Runtime library model은 기기 boot classpath V1입니다.

호스트 build 5270 이상이 필요합니다. Native library가 없으므로 순수 JVM universal APK 하나가 모든 기기 ABI를 지원합니다.

******

### 호스트 통합 상태

******

> runtime.loadJar의 raw 경로는 계속 기본 비활성 상태이며 호스트와 동일 서명의 exact component를 명시적으로 선택해야 합니다. R1은 R1.1 7/7, R1.2 4/4, canonical 실제 provider 매트릭스 7/7로 완료되었습니다. production Runtime single-flight는 인증된 key 확정 후 제한된 영구 의미 캐시를 사용합니다. 마지막 waiter를 포함한 어떤 인터럽트도 해당 호출자만 로컬 fallback 없이 분리하며 producer는 완료 후 캐시에 저장할 수 있습니다. last-waiter 협력 취소는 R2에 남고 safety circuit은 프로세스 수명 동안 보수적으로 유지됩니다.

******

### R1 설치 및 사용 가이드

******

이 경로는 기본적으로 꺼진 R1 명시적 opt-in 경로이며 설치만으로 활성화되는 대체 컴파일러가 아닙니다. R1 수용 증거는 이제 x86_64 에뮬레이터와 arm64 실제 기기에서 API 24/25/26/28/31/34/36 실제 provider 실행을 포함합니다. 이는 고정된 R1 gate를 닫은 것이며 경로 자동 활성화, 기본 컴파일러 승격 또는 제한된 V1 프로토콜 확장을 의미하지 않습니다.

#### 사전 조건

AutoJs6와 플러그인은 신뢰할 수 있고 서로 짝지어진 릴리스 출처에서만 받으세요. AutoJs6는 build 5270 이상이어야 하며 호스트와 플러그인의 현재 전체 서명 인증서 집합이 같아야 합니다. 직접 빌드할 때도 아래의 고정 package 및 service identity를 유지해야 합니다. 업그레이드 전에 스크립트와 중요한 앱 데이터를 백업하세요. Android가 서명 불일치를 알리면 호스트 제거 또는 데이터 삭제로 우회하지 마세요.

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### 설치 후 명시적으로 활성화

호환 AutoJs6를 먼저 설치하거나 업데이트한 다음 플러그인 APK를 설치하세요. AutoJs6에서 설정 > 앱 및 개발자 정보를 열고 앱 아이콘을 길게 눌러 개발자 옵션을 엽니다. DEX compiler > Raw JAR compiler provider에서 아래 exact component를 선택하고 확인하세요. 플러그인 설치만으로 경로가 켜지지 않으며 AutoJs6는 발견한 provider를 자동 선택하지 않습니다.

#### 상태 확인

개발자 옵션으로 돌아가 raw runtime.loadJar JAR가 아래 exact component를 우선 사용한다는 요약이 명확히 표시되는지 확인하세요. Built-in D8/dx 또는 후보 없음으로 표시되면 호스트 build, 두 package 이름, 플러그인 활성화 상태 및 서명을 확인하세요. 이 요약은 현재 선택과 discovery eligibility만 증명하며 특정 컴파일이 원격으로 수행되었다는 증거는 아닙니다. R1 매트릭스 완료 후에도 요청별 identity 재검증, handshake, 검증 및 fallback 규칙은 유지됩니다.

#### AutoJs6 예제

JVM `.class`가 들어 있는 읽기 가능한 JAR를 스크립트 옆 `lib/example.jar`에 두고 예제 class와 method를 그 JAR에 실제 존재하는 public API로 바꾸세요. 스크립트는 기존 `runtime.loadJar()` 진입점을 통해 선택한 provider를 사용합니다. 플러그인은 새로운 JavaScript global을 추가하지 않습니다.

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

이 예제는 raw JAR만 다룹니다. `.aar`, 미리 컴파일된 `.dex`, compatibility helper 및 동적 `defineClass()`는 항상 호스트 내장 경로에 남습니다. 검증이 신뢰할 수 없는 bytecode를 안전하게 만들지는 않으므로 신뢰하는 JAR만 로드하세요.

#### 진단 수집

문제를 보고할 때 AutoJs6 build/version, 플러그인 version, 개발자 옵션의 전체 exact-component 요약, 기기 model/API/ABI, 입력 JAR byte 수와 SHA-256, 발생 시각, 전체 스크립트 예외 및 재현 절차를 기록하세요. ADB를 사용한다면 각 명령의 `<serial>`에 권한이 있는 한 대의 기기 ID를 명시하고 실패 전후 AndroidClassLoader/AndroidRuntime 로그를 수집한 뒤 공유 전에 private path, 스크립트 내용 및 기타 민감한 정보를 제거하세요.

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 비활성화 및 긴급 롤백

개발자 옵션 > Raw JAR compiler provider에서 Built-in D8/dx를 선택하고 확인한 다음 AutoJs6를 중지하고 다시 시작하세요. 실험 경로는 꺼지지만 나중에 다시 선택할 수 있도록 component 기록은 유지됩니다. 긴급 롤백에서는 먼저 비활성화하고 호스트를 재시작하세요. AutoJs6 제거, 데이터 삭제 또는 스크립트 삭제는 필요하지 않습니다. 열린 process safety circuit은 해당 AutoJs6 process가 끝날 때까지 의도적으로 열린 상태를 유지합니다.

#### fallback 이해

경로가 꺼져 있거나 provider를 사용할 수 없거나 호환되지 않을 때, binding 또는 원격 작업 실패, timeout, 잘못된 출력, 검증된 artifact 채택 실패가 발생하면 한 번의 호출은 호스트 내장 D8/dx를 최대 한 번 시도할 수 있습니다. 이미 dispatch된 Binder 작업은 자동 재시도하지 않습니다. 호출자 cancel 또는 thread interruption은 local fallback 없이 전파됩니다. AAR, loadDex 및 defineClass는 이 플러그인을 사용하지 않습니다. 따라서 스크립트가 최종 성공했다는 사실만으로는 허용된 경로 중 하나가 성공했음을 알 수 있을 뿐 플러그인이 컴파일했다는 증거가 아닙니다.

#### 제거 및 복구

먼저 Built-in D8/dx를 선택하고 요약에서 실험이 꺼졌는지 확인한 다음 AutoJs6를 중지하고 플러그인을 제거하세요. 제거하면 플러그인 자체의 앱 데이터와 private temporary workspace가 영구 삭제되지만 호스트는 내장 컴파일러를 계속 사용할 수 있습니다. 복구할 때 호환되고 동일하게 서명된 플러그인을 설치하고 개발자 옵션에서 exact component를 다시 명시적으로 선택하세요. 이전 선택이 자동으로 활성화된다고 가정하지 마세요.

#### 알려진 제한 및 승인 경계

V1은 bounded raw JVM JAR-to-DEX-ZIP 변환만 수행합니다. R8 shrinking/obfuscation, 외부 classpath, custom desugared library, network compile 또는 deterministic byte output을 제공하지 않습니다. BUSY는 호스트 fallback으로 이어질 수 있으며 cancel 이후에도 D8 CPU 작업이 cleanup 완료까지 isolated process에서 계속될 수 있습니다. 마지막 waiter 이탈 뒤의 협력 취소는 R2에 남아 있으며 성능 승격, 기본 활성화 및 호스트 컴파일러 의존성 제거는 완료된 R1 범위 밖입니다.

******

### 개발 로드맵

******

R1은 완료되었습니다: R1.1 production 7/7, R1.2 automation 4/4, R1.3 실제 기기 매트릭스 7/7, 종료 조건 3/3. API 34 production routing 8/8, host DEX 16 suites/149 tests, wire 4/24, fake-provider 5/25 및 plugin 48 tests가 통과했고 lint는 0 error입니다. Canonical campaign f3c2b1af-be93-41e7-b541-f167f90e5cc1은 실제 provider 7개 cell을 모두 PASS했습니다: API 24/25 CLI, API 26/28/34/36 x86_64 D8Command, API 31 QV arm64 multi-user 실제 기기. journal head는 a5abaf62, runner SHA-256은 ca89ac16이며 이전 실패/의도적 종료 campaign은 보존됩니다. 경로는 기본 비활성 상태이고 last-waiter 협력 취소와 광범위한 복구 작업은 R2에서 미선택입니다.

- [체크 가능한 ROADMAP.md 열기](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### 보안

******

네트워크 또는 저장소 권한을 요청하지 않습니다. 서비스는 `org.autojs.permission.PLUGIN`으로 보호되며 AutoJs6 패키지 이름, 호출 UID 소유권 및 양쪽 서명 일치를 검증합니다. Descriptor는 비동기 작업 전에 복제됩니다. 임시 파일은 앱 전용 cache에만 두고 worker 종료 후 제거합니다.

******

### 운영 제한

******

- 압축 JAR은 64 MiB 및 20000 entries까지이고 전체 압축 해제 데이터는 256 MiB까지입니다.
- Class 데이터는 전체 128 MiB, class 하나당 8 MiB까지입니다. Entry 및 전체 압축 비율도 제한됩니다.
- DEX ZIP은 16 MiB 및 연속 index DEX entries 64개까지입니다. 요청에서 더 낮은 출력 상한을 선택할 수 있습니다.
- 프로세스에서 활성 컴파일 세션은 최대 1개입니다. Busy 요청은 재시도 가능한 BUSY 오류를 받습니다.
- 진단 데이터는 64 KiB까지입니다. 오류 텍스트와 callback queue에도 별도 상한이 있습니다.

******

### 제한 및 주의 사항

******

- Cancel 또는 close는 결과 게시를 즉시 막고 descriptor를 닫고 worker를 interrupt하지만 D8 CPU 작업을 안정적으로 중단할 수는 없습니다.
- 취소 후 D8 worker가 실제로 종료되고 cleanup이 끝날 때까지 세션 slot을 유지합니다. 그동안 새 요청은 BUSY를 받습니다.
- 결정성을 선언하지 않으며 외부 classpath 또는 사용자 지정 desugared library 구성을 받지 않습니다.
- 호스트는 완전한 DexIndexedZipValidator로 출력을 다시 검증합니다. 플러그인 packaging 검사는 호스트 검증을 대체하지 않습니다.
- 기기 runtime boot classpath는 시스템에 따라 다를 수 있습니다. 요청은 provider가 보고한 fingerprint와 일치해야 합니다.

******

### 릴리스 기록

******

# v1.0.0

###### 2026/08/08

* `기능` 플러그인 ID 및 엔진 `dex-compiler`, provider ID `autojs6-d8`, 변형 `d8`인 DEX Compiler 프로토콜 V1 provider
* `기능` DEBUG, RELEASE, minApi 24부터 36, multi-dex 및 기기 runtime boot classpath fingerprint를 지원하는 JAR에서 DEX ZIP 컴파일
* `기능` JAR 크기, entry 수, 압축 해제 데이터, class 데이터, 진단 및 출력 상한과 엄격한 ZIP framing, 이름 및 class magic 검증
* `기능` 연속 `classes*.dex` packaging과 실제 크기 및 SHA-256 보고, 호스트 DexIndexedZipValidator 재검증
* `기능` 단일 활성 세션, 동일 서명 AutoJs6 호출자 검사, 전용 작업 공간, API 24와 25 CLI fallback 및 보수적 취소 동작
* `기능` 순수 JVM universal APK 하나와 10개 언어 README, changelog, Android UI 및 플러그인 안내
* `의존성` D8 컴파일을 위해 R8 8.13.17 추가

##### 추가 릴리스

* [CHANGELOG-ko.md](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/assets/doc/CHANGELOG-ko.md)

******

### 빌드

******

```powershell
.\gradlew.bat :app:assembleDebug
```

릴리스 빌드:

```powershell
.\gradlew.bat :app:assembleRelease
```

설정은 `version.properties`에서 가져옵니다. 최소 SDK는 24, 대상 SDK는 36, 최소 JDK는 17이고 JDK 21을 권장합니다.

프로토콜 ABI는 `libs`의 저장소 로컬 AAR에서 제공됩니다:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

컴파일러는 Maven의 D8 8.13.17을 사용합니다. 로컬 AAR은 안정된 프로토콜 경계만 제공하며 결과는 native library가 없는 universal APK입니다.

******

### 라이선스

******

프로젝트 소스는 MPL-2.0으로 배포됩니다. R8 및 기타 타사 구성 요소에는 각각의 라이선스가 계속 적용됩니다.

******

### 리소스 구성

******

```text
.readme/lang_*.json
.changelog/lang_*.json
.python/generate_markdown.py
app/src/main/assets/doc/CHANGELOG-*.md
app/src/main/res/values-*/strings.xml
```

`.python/generate_markdown.py`는 JSON 소스에서 10개 언어 README와 앱 내 changelog를 생성합니다. Android 문자열은 각 리소스 디렉터리에서 관리합니다.

******

### 링크

******

- AutoJs6 문서: https://docs.autojs6.com
- R8 프로젝트: https://r8.googlesource.com/r8
