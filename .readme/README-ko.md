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

> 현재 AutoJs6 DEX adapter는 기본 비활성 experimental 기능이며 AndroidClassLoader에 연결되지 않았습니다. 이 플러그인만 설치해도 기존 기본 JAR-to-DEX 경로는 바뀌지 않습니다. End-to-end 사용에는 향후 host adapter 또는 호스트의 명시적 활성화와 이 compiler provider 선택이 필요합니다.

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
