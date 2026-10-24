# AutoChat v0.1.1 — standalone prototype

最大20フレーズを登録し、設定した秒数範囲から毎回待ち時間を抽選して送信します。送信先は取得可能なTextChannelから複数選択できます。RXDEVへの統合前の単体版です。

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/main/AutoChat.lua"))()
```

## v0.1.1の診断手順

Globalタブ未検出を調べるための試験版です。Globalの自動送信経路を追加した版ではありません。

1. AutoChatを再実行し、タイトルがv0.1.1であることを確認します。送信のSTARTは不要です。
2. 標準チャットをLOCAL/Hereにした状態で、黄色のSNAP / DIFFを押します。
3. WATCH 60sを押して、標準チャットをGLOBAL、FRIEND、LOCALへ手動で切り替えます。公開APIを1秒に1回、最大60秒監視します。STOP WATCHで早期終了できます。
4. GLOBALを表示した状態で、もう一度SNAP / DIFFを押します。手動スナップショット同士の差を比較できます。
5. Consoleの `[AutoChat DIAG] BEGIN` から `END`、またはWATCH stoppedの集計を確認します。

診断は送信を行いません。ただし通常のAutoChatを別途STARTしている場合、その送信タイマーは通常どおり動作します。

- BASE：初回の値。CHANGED / ADDED / REMOVED：前回から変化した値。
- NO METADATA CHANGE：調べた範囲の公開情報に変化なし。標準タブが存在しないという意味ではありません。
- UI label only：Global等のタブ表示の候補は見つかったが、送信経路は未確認。
- UNAVAILABLE / accessError：そのプロパティや領域にアクセスできなかったことを示します。
- TRUNCATED：探索上限に達したため、その領域をすべて調べてはいません。

公開チャンネル（RBXSystemを含む診断用一覧）、自分のCanSend、TargetTextChannel、チャット設定を記録します。手動SNAPではPlayerGui / CoreGuiのTextChannelWindow.Targetとタブ表示候補も調べます。通常の受信メッセージラベルや入力欄の本文、登録フレーズは記録しません。CoreGuiがアクセス禁止でも、取得できた範囲の診断は継続します。

探索はTextChatService最大256ノード、手動のみPlayerGui最大800 / CoreGui最大1600ノードです。WATCHは軽量なTextChatService側のみで、変化がない各秒の詳細ログを省きます。手動SNAPとWATCHの比較履歴は分離しています。終了・再実行時に監視を切断します。

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
- `v0.1.1/Engine.lua`: 設定検証、抽選、待ち時間、複数先への順次送信、キャンセル世代の管理。GUIから独立しています。
- `v0.1.1/RobloxChat.lua`: チャンネル検出、権限確認、標準チャットAPIの呼び出し。
- `v0.1.1/Diagnostics.lua`: 設定・チャンネル・UI参照先の読み取り専用診断、差分、60秒監視。
- `v0.1.1/App.lua`: 入力・複数選択・状態表示・ドラッグ・終了。mount(get)で明示的に起動します。

各子モジュールは読むだけでは起動しません。RXDEVに追加する際はモジュール取得関数を渡してApp.mountを呼ぶか、Engine.newに送信関数を渡して既存UIから操作できます。

スケジューラのHeartbeat接続は稼働中のみです。GUIの表示と検出フラグの確認は最大4Hzです。全ゲームオブジェクトを毎フレーム走査せず、TextChatServiceの一覧は変更時とREFRESH時に更新します。チャットのコールバックやユーザーが選択している通常の送信先は書き換えません。

ローカル検証では通信をモック化しています。実際のチャット送信・Global/Friendsタブの公開状況・GUIの見え方は実機検証が必要です。

参考：[TextChannel](https://create.roblox.com/docs/reference/engine/classes/TextChannel)、[TextSource](https://create.roblox.com/docs/reference/engine/classes/TextSource)、[送信結果](https://create.roblox.com/docs/reference/engine/enums/TextChatMessageStatus)、[Cross-server chat](https://create.roblox.com/docs/chat/cross-server-chat)。

