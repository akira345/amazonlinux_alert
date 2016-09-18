# AmazonLinux_Alert
RSSで配信されているAmazonLinuxのパッチ情報を取得し、配信します。

まだ試作品レベルです。

http://hamasyou.com/blog/2014/02/14/microsoft-translator-api/

ここを参考にMicrosoftTransferのクライアントID、シークレットキーを入手し、
config.ymlに設定します。

```
client_id: <クライアントID>
client_secret: <シークレットキー> 
mail_from: info@example.com
```

このプログラムはまだ登録するフロントエンドがないので、
データベースに直接セットします。


create_db.rbを開き、最後のほうにある以下の行を修正します。

```
    -- 送信先メアドと送信したいレベルを設定
    insert into users (id,mail) values (1,"user@example.com");
    insert into alert_levels (id,user_id,severity_level_id) values (1,1,3);
    insert into alert_levels (id,user_id,severity_level_id) values (2,1,2);
```

次に必要なテーブルを作成します。

```
ruby create_db.rb
```
Cronなどで１日１回程度以下のスクリプトを実行すると、RSSからデータを取得し、メール送信します。

```
ruby get_rss.rb
ruby cron.rb
```


