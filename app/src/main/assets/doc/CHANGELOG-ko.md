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
