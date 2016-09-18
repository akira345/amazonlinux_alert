# -*- coding: utf-8 -*-
#
# AmazonLinux RSSチェックスクリプト
# Ruby 2.2.4で作成

require 'pp'
require 'sqlite3'
require 'yaml'
require 'mail'
require 'rss'
require 'date'


# データベースとテーブル作成
database = SQLite3::Database.new("alas.db")

  database.execute_batch(<<-EOL
    CREATE TABLE IF NOT EXISTS alass (
      id integer primary key autoincrement,
      alas_code text unique,
      issue_overview text,
      issue_overview_jp text,
      issue_correction text,
      issue_correction_jp text,
      severity text,
      pubdate datetime,
      link text
    );
    CREATE TABLE IF NOT EXISTS packages (
      id integer primary key autoincrement,
      alas_id integer ,
      package text,
      FOREIGN KEY(alas_id) REFERENCES alass(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS cves (
      id integer primary key autoincrement,
      alas_id integer ,
      cve_code text,
      cve_details text,
      cve_details_jp text,
      FOREIGN KEY(alas_id) REFERENCES alass(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS users (
      id integer primary key autoincrement,
      mail text
    );
    CREATE TABLE IF NOT EXISTS alert_levels (
      id integer primary key autoincrement,
      user_id integer,
      severity_level_id integer,
      FOREIGN KEY(user_id) REFERENCES users(id)
    );
    CREATE TABLE IF NOT EXISTS severity_level (
      id integer primary key,
      severity text not null,
      severity_jp text,
      severity_level integer not null
    );
    CREATE TABLE IF NOT EXISTS send_histories (
      id integer primary key autoincrement,
      user_id integer,
      send_date datetime,
      FOREIGN KEY(user_id) REFERENCES users(id)
    );
    CREATE TABLE IF NOT EXISTS rss_get_histories (
      id integer primary key autoincrement,
      get_date datetime
    );
    insert into severity_level (severity,severity_level,severity_jp) values ("critical","緊急",3);
    insert into severity_level (severity,severity_level,severity_jp) values ("important","重要",2);
    insert into severity_level (severity,severity_level,severity_jp) values ("medium","警告",1);
    insert into severity_level (severity,severity_level,severity_jp) values ("low","注意",0);
    -- 送信先メアドと送信したいレベルを設定
    insert into users (id,mail) values (1,"user@example.com");
    insert into alert_levels (id,user_id,severity_level_id) values (1,1,3);
    insert into alert_levels (id,user_id,severity_level_id) values (2,1,2);
  EOL
  )

