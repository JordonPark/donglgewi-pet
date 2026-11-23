# 동글귀

동글귀는 사진에서 찾아낸 아이템으로 돌보고 함께 논 추억을 기억하는 2.5D 로컬 AI 펫입니다. Android와 iOS에서 Apple Vision 또는 ML Kit로 사진을 분류하고, Kanana 모델을 받아 기기에서 대화할 수 있습니다.

## 첫 시연

1. **설정 → 시연 새로 시작 · 첫날 18시**를 엽니다.
2. **가방 → 아이템 얻기 → 시연용 소풍 장면**에서 사과와 원반을 담고 먹이기와 원반 던지기를 해 봅니다.
3. **15시간 뒤 재방문**에서는 펫이 먼저 추억을 꺼냅니다. 첫날부터 다시 진행해 **24시간 뒤 재방문**을 하면, 먹이를 준 다음 추억을 꺼냅니다.

웹은 기본 대사와 사진의 수동 아이템 선택을 지원합니다. 실제 모델 추론은 모바일 설정에서 Kanana 모델을 받은 후 사용할 수 있습니다. 모델은 약 1.52GB이며 앱 설치본과 별도로 다운로드합니다.

## 개발

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d chrome
```

Android 앱 ID와 iOS 번들 ID는 모두 `com.jordonpark.donglgewi`입니다. iOS 16.4 이상을 대상으로 합니다. GitHub Actions의 **Donglgewi TestFlight**에서 **Build a Shorebird release for TestFlight**와 **Upload**를 선택하면 내부 테스트용 OTA 기준 빌드를 올립니다. 이 빌드를 설치한 후에는 **Publish a patch to the exact internal release**에 `0.1.0+3`처럼 해당 버전과 빌드 번호를 입력해 Dart 변경을 배포할 수 있습니다. 앱을 실행하면 패치를 확인하며, 내려받은 패치는 다음 실행부터 적용됩니다. 전체 빌드에는 Apple 팀 변수와 App Store Connect 키가, OTA 릴리스 및 패치에는 `SHOREBIRD_TOKEN`이 필요합니다.

[프로토타입 기획서](docs/local-llm-pet-prototype.md) · [Kanana 모델과 라이선스](assets/kanana-notice.txt) · [Noto Sans KR 라이선스](assets/pet/NotoSansKR-OFL.txt)
