# 部活動参加記録アプリ

Flutter と Supabase で作った、部活動の参加記録アプリです。

## 主な機能

- 名前とパスワードで部員登録・本人確認
- 自分の参加状態だけ登録
- 参加・遅刻・不参加の記録
- 日別の状態一覧
- 月別の参加・遅刻・不参加・活動日数集計

## Supabase設定

Supabase SQL Editorで以下を実行してください。

1. ベーステーブル作成SQL
2. `supabase_public_functions.sql`

`service_role` キーは絶対にブラウザやGitHubへ入れないでください。
このアプリに入っているのは公開用のanon / publishable keyです。

## Webビルド

```powershell
flutter pub get
flutter build web --release
```

生成された `build/web` をNetlifyなどに公開します。
