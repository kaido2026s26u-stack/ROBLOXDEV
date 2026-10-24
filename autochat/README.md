# AutoChat v0.1.4 — standalone prototype

最大20フレーズを登録し、設定した秒数範囲から毎回待ち時間を抽選して送信します。送信先は取得可能なTextChannelから複数選択できます。RXDEVへの統合前の単体版です。

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/main/AutoChat.lua"))()
```

## v0.1.4の絞り込み

調査のGUI対象を、CoreGui / PlayerGuiの直下に存在するAppChatとExperienceChatへ絞りました。TextChatServiceの設定・公開チャンネル、およびInput.TextBoxが参照する入力欄も調べます。それ以外の画面全体は探索しません。既知の名前で直下に見つからない場合はROOT STATUSにNOT FOUNDと明記します。別の位置・別名の実装は今回のGUI探索範囲外です。

- AppChat / ExperienceChatを個別に集計し、クラス・直下の子数・調べた件数をUI ROOTに表示します。空のFolderと未検出を区別できます。
- 構造表示は各ルート最大18行ずつです。一方の候補がもう一方を表示上限から押し出しません。
- CoreScript / Script / LocalScript / ModuleScriptは探索しません。VoiceChat / BubbleChatの枝、およびMessageList / MessageHistoryの子孫も省きます。除外した枝数を出します。
- Input.TextBoxの参照、入力欄の表示状態・編集可否・サイズは引き続き記録します。入力本文は読み書きしません。nilやアクセス失敗もそのまま表示します。
- UI内のテキストを調べる場合は、タブ・ナビゲーション候補の短い既知ラベルに限定します。通常のメッセージ本文は収集しません。

この版は調査範囲を意図的に絞っています。前版の全体ノード数と直接比較したり、今回の未検出だけで全クライアントから参照不能と判断したりしないでください。診断はGlobal送信の対応完了を意味しません。

## v0.1.4の一時調査ボタン

Global未検出を調べるため、日本語の「調査」ボタンに一本化しました。旧SNAP / DIFF・WATCH操作は不要です。

1. AutoChatを再実行し、タイトルがv0.1.4であることを確認します。
2. Roblox標準チャットでGLOBALを表示しておきます。
3. 黄色の「調査」を一度押し、そのまま完了を待ちます。送信のSTARTは不要です。
4. Consoleの `[AutoChat 調査 v0.1.4 #1]` の `REPORT BEGIN` から `調査完了 / REPORT END` までを共有してください。

通常は数秒で完了します。調査は一度だけ実行して接続を切断します。連打しても同時に重複起動しません。終了・再実行時は進行中の調査を中止します。

調査対象は、公開チャンネル・自身のCanSend・チャット設定・TargetTextChannelとTextBox参照の短時間の推移・TextChannelWindow.Target・チャットUI構造・タブ表示候補と親を含む表示状態です。チャット関連の名前を持つ枝を優先して探索します。アクセスできるTextChatServiceと、CoreGui / PlayerGui直下のAppChat / ExperienceChatを読みます。

前版の全体探索上限（CoreGui 1600 / PlayerGui 800）を改め、フレームごとに最大96ノード・約3msに分割し、全体は最大25000ノード・20秒で打ち切ります。TargetTextChannelの短時間観測を含め最低約3秒の調査です。時間切れ・ノード上限・アクセスエラー・詳細表示上限はレポートに明記します。レポートは結果の概要と限られた詳細行にまとめます。

TABが見つかっても、送信可能なチャンネルを取得できたとは限りません。Global-named channelsは名前にGlobalを含むTextChannelの数であり、Roblox標準Global経路の認定ではありません。調査範囲内での観測結果です。通常の受信メッセージラベル・入力本文・登録フレーズは収集せず、チャット関連UIの短いタブ名候補だけを記録します。

調査自体はチャットを送りません。通常のAutoChatをSTARTしている場合は、その送信は別に継続します。

## 操作

1. フレーズ欄へ1行1フレーズで入力します。空行は無視し、前後の空白は除きます。1〜20フレーズが必要です。
2. MIN/MAXに秒数を入力します。初期値は120〜240秒。MIN以上MAX以下から毎回抽選します。同じ値なら固定間隔です。最小1秒、有限の数値、MIN <= MAXで検証します。
3. 検出されたチャンネルをチェックします。最初はすべて未選択です。読み取り専用と確認できたものは選べません。権限を取得できないものはPermission unconfirmedと表示し、実際のAPI結果で判定します。
4. STARTで開始します。初回も抽選した時間を待ってから送信します。
5. 抽選したフレーズを送信します。フレーズは各回独立抽選のため、同じものが連続する場合があります。送信先は抽選せず、同じフレーズを選択先すべてへ1回ずつ順に送ります。
6. 設定変更はAPPLY / RESTARTで反映します。待ち時間も抽選し直します。STOPは設定を画面に残してタイマーを停止します。Xは終了して後始末します。

未反映の編集は動作中の設定を変えません。入力エラーのままAPPLYを押しても、それまでの有効な設定は動作を続けます。設定はメモリー内のみで、再実行すると初期状態です。再実行は旧パネルとタイマーを終了して置き換えます。

## 送信先の検出範囲

TextChatService配下のTextChannelを実際の名前で列挙し、RBXSystemを除外します。子孫の追加・削除、検出済みチャンネル名、TextSource.CanSendの変更で一覧を更新します。REFRESHでも再検出できます。選択中のチャンネルが削除された場合、次回の設定反映で候補から外れます。反映前の送信試行はUnavailableの結果になります。

GLOBAL / LOCAL / FRIENDなどの画面上のタブ名と、外部スクリプトに公開されるTextChannelは一致するとは限りません。Robloxのプラットフォーム側のGlobal/Friendsルートが公開されていない場合、そのタブは検出・送信できません。タブ名から架空の送信経路は作りません。

## 状態と制約

標準のTextChannel:SendAsyncを呼び、TextChatMessageStatus.Successの場合だけAPI successを数えます。API成功は他のユーザーへの実際の配信確認ではありません。フィルター・権限・連投制限・モデレーション等の結果はFailedと理由に出します。例外もチャンネルごとに扱い、残りの選択先への試行を続けます。失敗を即時連投で再試行しません。

公式仕様にはユーザー自身が入力・送信したメッセージのみ配信される制約があります。Deltaからの自動送信が届くかは実機で別途確認してください。アクセス制限を回避する送信経路は使いません。

STOPは未開始の送信を取り消します。すでに開始したSendAsyncの取り消しはできません。その応答待ちの間にSTOPした場合も、残りの送信先への処理は止まり、古い完了結果が再開後のタイマーを書き換えることはありません。

## モジュール構成

- `AutoChat.lua`: 起動用。子モジュールは1つのコミットSHAに固定し、同じ起動内では再利用します。
- `v0.1.4/Engine.lua`: 設定検証、抽選、待ち時間、複数先への順次送信、キャンセル世代の管理。GUIから独立しています。
- `v0.1.4/RobloxChat.lua`: チャンネル検出、権限確認、標準チャットAPIの呼び出し。
- `v0.1.4/Diagnostics.lua`: チャット優先の一回調査、フレーム分割、結果レポート、自動終了。
- `v0.1.4/App.lua`: 入力・複数選択・状態表示・ドラッグ・終了。mount(get)で明示的に起動します。

各子モジュールは読むだけでは起動しません。RXDEVに追加する際はモジュール取得関数を渡してApp.mountを呼ぶか、Engine.newに送信関数を渡して既存UIから操作できます。

スケジューラのHeartbeat接続は稼働中のみです。GUIの表示と検出フラグの確認は最大4Hzです。全ゲームオブジェクトを毎フレーム走査せず、TextChatServiceの一覧は変更時とREFRESH時に更新します。チャットのコールバックやユーザーが選択している通常の送信先は書き換えません。

ローカル検証では通信をモック化しています。実際のチャット送信・Global/Friendsタブの公開状況・GUIの見え方は実機検証が必要です。

参考：[TextChannel](https://create.roblox.com/docs/reference/engine/classes/TextChannel)、[TextSource](https://create.roblox.com/docs/reference/engine/classes/TextSource)、[送信結果](https://create.roblox.com/docs/reference/engine/enums/TextChatMessageStatus)、[Cross-server chat](https://create.roblox.com/docs/chat/cross-server-chat)。

