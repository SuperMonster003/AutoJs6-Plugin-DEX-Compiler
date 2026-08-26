<!--suppress HtmlDeprecatedAttribute, HttpUrlsUsage -->

<div align="center">
  <p>
    <img src="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/app/src/main/res/mipmap/ic_launcher_dex.png?raw=true" alt="dex-compiler-ic-launcher" border="0" width="128" />
  </p>

  <p>AutoJs6용 독립 DEX 컴파일러 플러그인. 격리된 프로세스에서 최신 D8로 스크립트 JAR을 DEX로 컴파일</p>

  <p>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/releases"><img alt="GitHub release (latest by date)" src="https://img.shields.io/github/v/release/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?label=Release"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/issues"><img alt="GitHub closed issues" src="https://img.shields.io/github/issues/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=A24232&label=Issues"/></a>
    <a href="https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/LICENSE"><img alt="GitHub License" src="https://img.shields.io/github/license/SuperMonster003/AutoJs6-Plugin-DEX-Compiler?color=534BAE&label=License"/></a>
  </p>
</div>

******

### 언어

******

README.md는 현재 다음 언어로 제공됩니다:

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

AutoJs6 스크립트는 `runtime.loadJar()`로 JAR을 로드하고 그 안의 Java 클래스를 호출할 수 있습니다. Android는 JVM 바이트코드를 직접 실행할 수 없으므로 JAR은 먼저 DEX로 컴파일되어야 하며, 기본적으로 이 단계는 AutoJs6 내장 컴파일러가 처리합니다.

이 플러그인은 또 다른 선택지를 제공합니다: 별도로 설치되는 앱으로서, 자체 격리 프로세스 안에서 더 새로운 버전의 Google D8 컴파일러로 이 컴파일을 수행합니다. AutoJs6는 JAR을 플러그인에 맡기고 DEX 결과를 돌려받은 뒤 스스로 검증, 캐시, 로드합니다; 플러그인에 문제가 생기면 AutoJs6가 자동으로 내장 컴파일러로 되돌아가므로 스크립트는 보통 영향을 받지 않습니다.

다음과 같은 경우에 이 플러그인이 적합합니다: AutoJs6에 내장된 것보다 새로운 D8을 쓰고 싶을 때; 컴파일이 AutoJs6와 격리된 프로세스에서 실행되길 원할 때; AutoJs6 업데이트와 무관하게 컴파일러만 따로 업그레이드하고 싶을 때.

******

### 동작 원리

******

플러그인을 활성화하면 `runtime.loadJar()` 호출은 대략 다음 단계를 거칩니다:

```text
1. script     calls runtime.loadJar() or runtime.loadJarWithClasspath()
2. AutoJs6    validates and freezes the input JAR, records its size and SHA-256
3. plugin     re-verifies the input, then compiles it with D8 in a private sandboxed process
4. plugin     returns a DEX ZIP (classes.dex, classes2.dex, ...)
5. AutoJs6    independently re-validates the result, caches it, and loads the classes
*  fallback   if anything fails, AutoJs6 retries once with its built-in compiler
```

플러그인이 담당하는 것은 3단계와 4단계, 즉 "컴파일" 자체뿐입니다; 입력 고정, 결과 검증, 캐시와 최종 클래스 로딩은 항상 AutoJs6 안에서 이루어집니다. 두 앱은 Binder를 통해 파일 디스크립터만 주고받으므로, 플러그인은 스크립트 디렉터리를 읽지 않으며 원본 파일 경로도 알 수 없습니다. 컴파일 결과는 입력 내용과 컴파일 매개변수 기준으로 캐시되므로, 같은 입력을 다시 로드하면 재컴파일 없이 캐시에 적중합니다.

******

### 기능

******

- 컴파일은 D8 8.13.22가 수행하며, 플러그인은 AutoJs6와 독립적으로 컴파일러를 업데이트할 수 있습니다.
- 컴파일은 플러그인 자체의 독립 프로세스와 사설 작업 공간에서 실행되어, 충돌이나 실패가 AutoJs6 메인 프로세스에 영향을 주지 않습니다.
- 이중 검증: 플러그인은 컴파일 전에 JAR의 크기, SHA-256, ZIP 구조, class 내용을 대조하고, AutoJs6는 컴파일 후 DEX 출력을 독립적으로 재검증합니다.
- DEBUG 및 RELEASE 컴파일 모드, multi-dex 출력, minApi 24부터 36까지의 컴파일 매개변수를 지원합니다.
- Android 7.0 (API 24) 이상의 모든 기기를 지원합니다; API 26+는 D8Command를 사용하고 API 24/25는 자동으로 D8 CLI 호환 경로로 전환됩니다.
- V1.1 프로토콜은 순서 있는 컴파일 타임 classpath (`runtime.loadJarWithClasspath()`)를 지원하여, 외부 API를 참조하는 JAR을 컴파일할 수 있습니다.
- 어떤 실패든 AutoJs6가 최대 1회 내장 컴파일러로 폴백하므로, 스크립트가 플러그인에서 멈춰버리는 일은 없습니다.

******

### 설치 및 사용

******

플러그인 활성화는 세 단계입니다: 호환되는 AutoJs6 설치, 이 플러그인 APK 설치, 그리고 AutoJs6 개발자 옵션에서 플러그인을 수동 선택. 미리 알아둘 두 가지:

- 플러그인은 기본적으로 비활성입니다. 설치만으로는 AutoJs6의 어떤 동작도 바뀌지 않으며, 아래 절차대로 수동 활성화가 필요합니다.
- 언제든 되돌릴 수 있습니다. 개발자 옵션에서 Built-in D8/dx로 다시 전환하면 아무것도 제거하지 않고 원래 동작으로 돌아갑니다.

#### 사전 조건

- AutoJs6 build 5270 이상 (`runtime.loadJar()`용); `runtime.loadJarWithClasspath()`에는 더 새로운 페어 호스트 빌드가 필요합니다 (검증에는 build 5274 사용).
- 호스트와 플러그인은 같은 신뢰할 수 있는 출처에서 받아야 하며 서명이 일치해야 합니다. 서명이 다르면 플러그인을 선택할 수 없습니다; 페어로 배포된 패키지를 쓰거나 둘 다 직접 빌드하고, 호스트 제거나 데이터 삭제로 우회하지 마세요.
- 직접 빌드할 때는 아래의 고정된 패키지 이름과 서비스 컴포넌트를 그대로 유지하세요.
- 업그레이드 전에 스크립트와 중요한 데이터를 백업해 두는 것이 좋습니다.

관련 식별자는 다음과 같습니다:

```text
host package: org.autojs.autojs6
plugin package: io.github.supermonster003.autojs6.plugin.dexcompiler
minimum host build: 5270
exact component: io.github.supermonster003.autojs6.plugin.dexcompiler/io.github.supermonster003.autojs6.plugin.dexcompiler.DexCompilerService
```

#### 설치 및 활성화

1. 호환 버전의 AutoJs6를 설치하거나 업그레이드합니다.
2. 이 플러그인 APK를 설치합니다.
3. AutoJs6를 열고 설정 > 앱 및 개발자 정보로 이동한 뒤, 앱 아이콘을 길게 눌러 개발자 옵션에 들어갑니다.
4. DEX compiler > Raw JAR compiler provider로 이동합니다.
5. 이 플러그인의 서비스 컴포넌트 (위의 exact component)를 선택하고 확인합니다.

다시 강조하면: 플러그인 설치만으로는 활성화되지 않으며, AutoJs6는 발견된 provider를 자동 선택하지 않습니다; 3~5단계는 필수입니다.

#### 활성화 확인

개발자 옵션 페이지로 돌아가서 요약에 이 플러그인의 서비스 컴포넌트가 선택된 것으로 표시되면 활성화 성공입니다: 이후 스크립트의 `runtime.loadJar()`와 `runtime.loadJarWithClasspath()` 컴파일은 우선적으로 플러그인에 맡겨집니다.

목록에서 플러그인을 찾을 수 없거나 요약이 여전히 Built-in D8/dx라면, 순서대로 확인하세요: AutoJs6 build가 5270 이상인지; 호스트와 플러그인의 패키지 이름이 위와 일치하는지; 플러그인 앱이 시스템에 의해 비활성화되지 않았는지; 두 서명이 일치하는지.

참고: 이 요약은 "현재 누가 선택되어 있는가"를 나타낼 뿐, "특정 컴파일을 실제로 누가 수행했는가"가 아닙니다; 개별 컴파일은 캐시 적중이나 폴백으로 인해 여전히 플러그인을 거치지 않을 수 있습니다 (아래 참조).

#### 스크립트 예제

JVM `.class` 파일이 들어 있는 JAR을 스크립트 디렉터리의 `lib/example.jar`에 두고 평소처럼 `runtime.loadJar()`를 호출하면 됩니다; 플러그인은 새로운 JavaScript 전역 객체를 추가하지 않으며, 스크립트 작성 방식은 내장 컴파일러를 쓸 때와 완전히 같습니다. 예제의 클래스 이름과 메서드는 여러분 JAR에 실제로 존재하는 public API로 바꾸세요.

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

실행 환경에는 존재하지만 JAR 자체에는 없는 클래스 (예: API 스텁)를 컴파일 시 참조한다면, 명시적인 컴파일 타임 classpath 진입점을 사용할 수 있습니다:

```javascript
runtime.loadJarWithClasspath(
    files.path("./lib/program.jar"),
    files.path("./lib/compile-api-stubs.jar"),
);
```

classpath에 대해 알아둘 세 가지:

- classpath JAR은 컴파일 타임 참조 해석에만 쓰이며, 출력에 포함되지도 자동 로드되지도 않습니다.
- 프로그램이 런타임에 그 클래스들을 실제로 쓴다면, 그것들은 최종 클래스 로더의 parent 체인 (Android 시스템 클래스나 AutoJs6 동봉 클래스 등)에 이미 존재해야 합니다. 의존성 JAR을 먼저 `runtime.loadJar()`로 로드해도 형제 로더만 생길 뿐 이 조건을 만족하지 못합니다.
- classpath 선언 순서는 의미가 있으며 캐시 식별자의 일부입니다; 이 진입점에는 classpath JAR이 최소 1개 필요합니다.

한편 `.aar` 파일, 컴파일된 `.dex`, `defineClass()` 같은 동적 진입점은 항상 AutoJs6 내장 경로로 처리되며 이 플러그인과 무관합니다. 마지막으로, 컴파일은 보안 검사가 아닙니다: 신뢰하는 JAR만 로드하세요.

#### 컴파일이 실패하면 어떻게 되나요

플러그인을 활성화해도 AutoJs6는 여전히 "스크립트가 계속 돌아가는 것"을 최우선으로 둡니다:

- `runtime.loadJar()`: 플러그인을 쓸 수 없거나, 컴파일이 실패하거나, 시간이 초과되거나, 출력이 검증을 통과하지 못하면 AutoJs6가 같은 JAR을 내장 D8/dx로 자동 재컴파일합니다 (요청당 최대 1회).
- `runtime.loadJarWithClasspath()`: 폴백 역시 최대 1회이며, 완전히 동일한 program과 classpath를 로컬 D8에 넘겨야 합니다; classpath를 버리거나 조용히 다운그레이드하지 않습니다.
- 의도적인 취소 (예: 스크립트 중지)는 실패가 아닙니다: 폴백을 유발하지 않고 해당 로드를 그대로 끝냅니다.
- 플러그인이 BUSY를 반환하면 (동시에 하나의 컴파일 세션만 허용), AutoJs6는 위 규칙대로 처리합니다; 잠시 후 스크립트를 다시 실행하면 됩니다.

따라서 스크립트가 성공적으로 실행되었다는 사실만으로는 그 컴파일이 플러그인을 거쳤다고 증명할 수 없습니다; 확실히 알아야 할 때는 아래의 진단 절차를 쓰세요.

#### 문제 해결 및 제보

플러그인이 오작동하는 것 같으면 먼저 Built-in D8/dx로 전환해 동작이 달라지는지 비교해 보세요. 문제를 제보할 때는 가능한 한 다음 정보를 함께 제공해 주세요:

- AutoJs6 build/버전, 플러그인 버전, 개발자 옵션 요약에 표시된 전체 컴포넌트 이름.
- 기기 모델, Android 버전 (API), CPU 아키텍처 (ABI).
- 문제를 일으키는 JAR (또는 그 바이트 수와 SHA-256), 전체 스크립트 예외 정보와 재현 절차.

ADB를 다룰 수 있다면 다음 명령으로 관련 로그를 수집할 수 있습니다 (`<serial>`은 기기 일련번호로 바꾸고, 공유 전에 로그의 사적 경로와 민감한 내용을 제거하세요):

```powershell
adb -s <serial> shell dumpsys package org.autojs.autojs6
adb -s <serial> shell dumpsys package io.github.supermonster003.autojs6.plugin.dexcompiler
adb -s <serial> logcat -d -v threadtime AndroidClassLoader:D AndroidRuntime:E *:S
```

#### 비활성화, 롤백, 제거

- 일시적 비활성화: 개발자 옵션의 Raw JAR compiler provider에서 Built-in D8/dx를 선택해 확인한 뒤 AutoJs6를 완전히 종료하고 재시작합니다. 컴포넌트 선택 기록은 유지되므로 언제든 다시 활성화할 수 있습니다.
- 긴급 상황: 위 방법으로 비활성화하고 호스트를 재시작하면 충분합니다; AutoJs6 제거, 데이터 삭제, 스크립트 삭제는 필요 없습니다.
- 플러그인 제거: 먼저 Built-in D8/dx로 전환한 다음 AutoJs6를 중지하고 플러그인 APK를 제거합니다. 제거하면 플러그인 자체의 모든 데이터와 임시 파일이 삭제됩니다; AutoJs6는 내장 컴파일러로 계속 동작합니다.
- 재설치 후에는 다시 수동으로 활성화해야 하며, 이전 선택이 자동 복원되지 않습니다.

******

### 자주 묻는 질문

******

**Q: 플러그인을 설치했는데 아무 변화가 없습니다. 고장인가요?**

A: 아닙니다. 플러그인은 기본적으로 꺼져 있으며 개발자 옵션에서 수동 활성화가 필요합니다 (위 참조); 또한 `runtime.loadJar()`와 `runtime.loadJarWithClasspath()`의 컴파일 단계에만 영향을 주고 스크립트의 다른 동작은 바꾸지 않습니다.

**Q: 특정 컴파일이 정말 플러그인에서 수행되었는지 어떻게 확인하나요?**

A: 개발자 옵션 요약은 "플러그인이 선택됨"만을 뜻합니다. 실패 시 자동 폴백되고 결과는 캐시되므로, 스크립트 성공만으로는 플러그인이 컴파일했다고 단정할 수 없습니다; "문제 해결 및 제보" 절차대로 로그를 수집해 확인하세요.

**Q: 이 플러그인을 쓰면 스크립트가 빨라지나요?**

A: 목표는 더 새로운 컴파일러, 더 엄격한 입력 검증, 프로세스 격리이지 성능이 아닙니다. 컴파일 소요 시간은 내장 컴파일러와 대체로 비슷하며, 컴파일 결과는 AutoJs6가 캐시합니다.

**Q: R8 축소/난독화를 지원하나요? RELEASE 모드가 R8인가요?**

A: 둘 다 아닙니다. 이 플러그인은 D8 컴파일만 수행합니다; `RELEASE`는 D8의 release 컴파일 모드를 고르는 것일 뿐 shrinking, obfuscation, mapping을 포함하지 않습니다. R8 기능은 별도의 독립된 provider 플러그인 소관입니다.

**Q: 왜 호스트와 플러그인의 서명이 일치해야 하나요?**

A: 양방향 보안 검증입니다: 다른 앱이 AutoJs6를 사칭해 플러그인을 호출하는 것과, 변조된 플러그인이 컴파일 서비스를 사칭하는 것을 막습니다. 서명이 다르면 페어로 배포된 패키지로 교체하고, 제거나 데이터 삭제로 우회하지 마세요.

**Q: 플러그인이 네트워크에 접속하거나 내 파일을 읽나요?**

A: 아니요. 플러그인에는 네트워크와 저장소 권한이 없으며, AutoJs6가 파일 디스크립터로 건네준 내용만 읽을 수 있습니다. 임시 파일은 전부 자체 사설 디렉터리에 있습니다.

******

### 범위의 경계

******

오해를 피하기 위해, 다음은 이 플러그인의 기능 범위에 명시적으로 포함되지 않습니다:

- R8 shrinking, optimization, obfuscation을 하지 않으며 mapping 파일도 생성하지 않습니다; `RELEASE`는 D8의 release 컴파일 모드를 선택할 뿐입니다.
- 의존성 다운로드나 해석을 하지 않고 (Maven/Gradle 통합 없음), 네트워크 컴파일도 하지 않습니다.
- `.aar` 파일, 컴파일된 `.dex`, 동적 `defineClass()` 바이트코드를 처리하지 않습니다; 이들은 항상 AutoJs6 내장 경로를 따릅니다.
- V1.1 classpath는 컴파일 전용입니다: 런타임 의존성을 포장하지 않으며 결합 클래스 로더도 만들지 않습니다.
- 바이트 수준의 결정적 출력을 보장하지 않습니다: 같은 입력이라도 컴파일러 버전에 따라 다르지만 등가인 DEX가 나올 수 있습니다.
- AutoJs6의 출력 검증을 대체하지 않습니다: 호스트는 항상 DEX 결과를 독립적으로 재검증합니다.
- 자동으로 기본 컴파일러가 되지 않습니다: 활성화 여부는 항상 사용자의 명시적 결정입니다.

******

### 기술 레퍼런스

******

다음 내용은 정밀한 경계가 필요한 개발자와 통합 담당자를 위한 것입니다; 플러그인을 사용하기만 한다면 보통 읽지 않아도 됩니다.

#### 입력과 출력

프로토콜 V1.0은 입력 디스크립터를 통해 raw program JAR 하나를 받습니다; V1.1은 같은 유계 입력 번들 안에서 program JAR 하나와 순서 있는 컴파일 타임 classpath JAR 최소 하나를 받습니다. 둘 다 같은 형태의 출력을 생성합니다:

```text
input: JAR with JVM class files
output: DEX ZIP with contiguous classes*.dex entries
compiler: D8 8.13.22
```

#### 플러그인 발견 식별자

호스트는 다음 식별자로 플러그인을 발견하고 호출합니다:

```text
service action: org.autojs.plugin.DEX_COMPILER
plugin id: dex-compiler
protocol provider id: autojs6-d8
engine: dex-compiler
variant: d8
protocol: V1
required host build: 5270
```

플러그인은 D8 8.13.22, 프로토콜 범위 V1.0~V1.1, JAR 입력, DEX ZIP 출력, DEBUG 및 RELEASE 모드, minApi 24~36, multi-dex를 선언합니다; runtime library model은 기기 boot classpath V1입니다.

build 5270는 V1.0의 최소 호스트 요건입니다; `runtime.loadJarWithClasspath()`에는 V1.1을 지원하는 페어 호스트 빌드가 필요합니다 (대표 검증에는 build 5274 사용). 플러그인은 native library를 포함하지 않으며, 순수 JVM universal APK 하나로 모든 기기 ABI를 지원합니다.

#### 보안 모델

플러그인은 네트워크와 저장소 권한을 요청하지 않습니다. 컴파일 서비스는 `org.autojs.permission.PLUGIN` 권한으로 보호되며, 매 호출마다 AutoJs6 패키지 이름, 호출자 UID, 양측 서명을 검증합니다. 입출력은 파일 디스크립터로 전달되어 비동기 처리 전에 복사되며, 임시 파일은 플러그인 사설 cache에만 존재하고 컴파일 종료 후 정리됩니다.

#### 리소스 상한

악의적이거나 비정상적인 입력을 방어하기 위해 플러그인은 각 단계에 고정 상한을 두며, 이를 초과하는 요청은 즉시 거부됩니다:

- 입력 JAR: 압축 기준 최대 64 MiB, entry 최대 20000개, 압축 해제 총량 최대 256 MiB.
- V1.1 classpath: 최대 32개 JAR, 압축 JAR 하나당 최대 64 MiB, classpath 압축 총량 최대 128 MiB, 입력 번들 전체 최대 256 MiB.
- class 데이터: 총량 최대 128 MiB, class 하나당 최대 8 MiB; entry별 및 전체 압축비에도 제한이 있습니다.
- 출력 DEX ZIP: 최대 16 MiB, 연속 번호의 DEX entry 최대 64개; 요청 측에서 더 낮은 상한을 선언할 수 있습니다.
- 동시성: 프로세스당 동시에 하나의 컴파일 세션만 처리하며, 그 외 요청은 재시도 가능한 BUSY 오류를 받습니다.
- 진단 데이터는 최대 64 KiB이며, 오류 텍스트와 콜백 큐에도 별도의 상한이 있습니다.

#### 주의 사항

- 취소나 종료는 결과 게시를 즉시 차단하고 worker를 중단시키지만, D8 내부의 CPU 작업은 확실히 멈출 수 없어 현재 컴파일이 반환될 때까지 격리 프로세스에서 계속될 수 있습니다.
- 취소 후 세션 슬롯은 worker가 실제로 종료되고 정리가 끝날 때까지 점유되며, 그동안 새 요청은 BUSY를 받습니다.
- 플러그인은 결정적 출력을 선언하지 않습니다; 캐시 식별자에 컴파일러 버전과 런타임 지문이 포함되므로 버전이 바뀌어도 오래된 결과를 잘못 쓰지 않습니다.
- V1.1은 호스트가 동결해 포장한 컴파일 타임 classpath만 받습니다; 호출자의 파일 경로나 사용자 정의 desugared library 구성은 받지 않습니다.
- 기기의 runtime boot classpath는 시스템마다 다르며, 요청은 provider가 보고한 runtime 지문과 일치해야 합니다.

******

### 개발 로드맵

******

개발은 단계별로 진행되며 R0부터 R4까지 검토 가능한 증거와 함께 완료되었습니다. R5는 진행 중입니다: 사용자 안내서와 앱 내 설명을 다시 작성했고 제한 및 비식별화된 진단, 프로세스 메모리에만 남는 최근 경로 요약, 승인된 Android 실패/복구 사례를 완료했습니다; 독립 테스터도 ‘설치 → 활성화 → 예제 스크립트 실행’을 막힘없이 마쳤습니다. R5.2 벤치마크와 수치 승격 정책은 완료됐습니다. 병렬 처리를 제한한 후보는 결합 P95 PSS 6/6을 통과했지만, 수정된 프로세스 콜드 cache-hit added P95 지연 시간 3개 셀이 모두 100 ms를 초과해 아직 승격되지 않았습니다. R5.3도 완료됐습니다: D8 8.13.22를 포함한 v1.1.0을 고정했고 최종 페어 APK가 API 24/x86, API 34/x86_64, API 35/arm64의 대표 실제 provider classpath 셀을 통과했으며, 두 클린 디렉터리 조사에서 출력을 생성한 54개 셀의 디렉터리 간 출력 다이제스트 차이가 0이었고 `determinismClaim=NOT_CLAIMED`를 유지했습니다. R5.4의 독립 R8 provider 공개 릴리스 조정은 아직 남아 있습니다. 각 항목의 완료 정의와 증거는 다음을 참조하세요:

- [체크 가능한 ROADMAP.md 열기](https://github.com/SuperMonster003/AutoJs6-Plugin-DEX-Compiler/blob/master/ROADMAP.md)

******

### 릴리스 기록

******

# v1.1.0

###### 2026/08/27

* `힌트` `runtime.loadJarWithClasspath()`에는 페어로 제공되는 AutoJs6 build 5274 이상이 필요합니다; 일반 `runtime.loadJar()`는 계속 build 5270 이상과 호환됩니다
* `기능` V1.1 순서 지정 컴파일 타임 classpath 지원 추가: program JAR가 외부 API JAR를 참조할 수 있으며, classpath 입력은 컴파일에만 사용되고 DEX에 패키징되거나 자동으로 로드되지 않습니다
* `수정` 선언된 길이가 파일 경계에서 정확히 끝나는 표준 제한형 ZIP/JAR archive comment를 허용하면서 모호한 EOCD, 불일치 길이 및 후행 데이터는 계속 거부
* `수정` 축소된 Release 빌드에서도 내장 D8 엔진과 서비스 제공자를 유지하여 프로덕션 APK가 JAR 입력을 컴파일할 수 있도록 수정
* `개선` 사용 가능한 source, archive entry, 위치 메타데이터를 포함한 크기 제한 및 민감 정보 제거 D8 info/warning/error 진단을 제공하여 플러그인 컴파일 실패를 더 쉽게 조사할 수 있습니다
* `개선` D8 내부 병렬 컴파일을 작업자 스레드 2개로 제한해 출력 및 캐시 의미를 바꾸지 않고 대형 JAR 콜드 컴파일의 최대 메모리를 줄임
* `의존성` 번들 Google R8 라이브러리를 8.13.22로 업그레이드 (D8 컴파일러 제공)

# v1.0.0

###### 2026/08/08

* `힌트` 첫 안정 릴리스. 설치 후 기본적으로 비활성 상태이며, AutoJs6 개발자 옵션에서 수동으로 활성화해야 합니다; 절차는 README의 "설치 및 사용" 장을 참조하세요
* `기능` AutoJs6의 외부 DEX 컴파일러 플러그인으로 동작: 스크립트가 `runtime.loadJar()`로 JAR을 로드할 때, 내장 컴파일러 대신 이 플러그인이 JAR에서 DEX로의 컴파일을 수행할 수 있습니다
* `기능` 컴파일은 플러그인 자체 프로세스 안의 사설 샌드박스에서 실행되어 AutoJs6와 격리됩니다; 플러그인이 실패하거나 사용 불가하면 AutoJs6가 최대 1회 내장 컴파일러로 폴백합니다
* `기능` 컴파일 전에 입력 JAR의 크기, SHA-256, ZIP 구조, entry 이름, class 내용을 엄격히 검증하여 비정상적이거나 한도를 초과하거나 변조된 입력을 거부합니다
* `기능` DEBUG 및 RELEASE 컴파일 모드, multi-dex 출력, minApi 24~36을 지원; 출력은 연속 번호의 `classes*.dex` ZIP이며 실제 크기와 SHA-256을 보고합니다
* `기능` Android 7.0 (API 24) 이상 기기와 호환; API 26+는 D8Command를 사용하고 API 24/25는 자동으로 D8 CLI 호환 경로를 사용합니다
* `기능` 동일 서명의 AutoJs6와만 통신하며 (`org.autojs.permission.PLUGIN` 권한으로 보호), 네트워크 및 저장소 권한을 요청하지 않습니다
* `기능` 순수 JVM 구현으로 단일 universal APK가 모든 기기 아키텍처를 지원; 10개 언어의 UI, README, 앱 내 설명 포함
* `의존성` Google R8 라이브러리 8.13.17 동봉 (D8 컴파일러 제공)

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

빌드 매개변수는 `version.properties`에서 옵니다. 현재 최소 SDK는 24, 대상 SDK는 36, 최소 JDK는 17이며 JDK 21을 권장합니다.

프로토콜 ABI는 저장소 `libs` 디렉터리의 로컬 AAR이 제공합니다:

```text
common-plugin-api.aar
protocol-wire-api.aar
dex-compiler-api.aar
```

컴파일러는 Maven을 통해 D8 8.13.22로 도입됩니다. 로컬 AAR은 안정적인 프로토콜 경계만 제공하며, 빌드 산출물은 native library가 없는 universal APK입니다.

******

### 라이선스

******

프로젝트 소스 코드는 MPL-2.0을 사용합니다. R8과 기타 서드파티 구성 요소에는 계속 각자의 라이선스가 적용됩니다.

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

`.python/generate_markdown.py`는 JSON 소스로부터 전체 10개 언어의 README와 앱 내 변경 로그를 생성합니다; 문서를 수정할 때는 생성된 Markdown이 아니라 JSON 소스를 편집하세요. Android UI 문자열은 각자의 리소스 디렉터리에서 관리됩니다.

******

### 링크

******

- AutoJs6 문서: https://docs.autojs6.com
- R8 프로젝트: https://r8.googlesource.com/r8
