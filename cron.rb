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
require 'erb'

def get_cves_data(alas_id, db)
  # Alasに対応するCVEを取得
  cves = []
  db.prepare('select cve_code,cve_details_jp from cves where alas_id = ? order by id') do |stmt|
    stmt.execute(alas_id).each do |ret|
      tmp = {}
      tmp[:cve_code] = ret[0]
      tmp[:cve_details_jp] = str_format(ret[1],20,4)
      cves.push(tmp)
    end
  end
  cves
end

def get_alass_data(severity, db)
  alass = []
  # 重要度に対するAlasを取得
  # 最後に取得した日以降に取得したものが対象
  db.prepare('select a.id,a.alas_code,a.issue_overview_jp,a.issue_correction_jp,a.pubdate from (select max(get_date) as last_day from rss_get_histories h ) h,alass a where h.last_day < a.pubdate and severity = ? order by pubdate desc') do |stmt|
    stmt.execute(severity).each do |ret|
      tmp = {}
      alas_id = ret[0]
      tmp[:alas_code] = ret[1]
      tmp[:issue_overview_jp] = str_format(ret[2],20,4)
      tmp[:issue_correction_jp] = str_format(ret[3],20,4)
      tmp[:pubdate] = ret[4]
      # パッケージ情報取得
      tmp[:packages] = get_packages_data(alas_id, db)
      # CVE情報取得
      tmp[:cves] = get_cves_data(alas_id, db)

      alass.push(tmp)
    end
  end
  alass
end

def get_packages_data(alas_id, db)
  packages = []
  # Alasに対応するパッケージを取得
  db.prepare('select package from packages where alas_id = ? order by id') do |stmt|
    stmt.execute(alas_id).each do |ret|
      packages.push(ret[0])
    end
  end
  packages
end

def get_data(user_id, db)
  datas = []
  # ユーザが設定した送信する重要度セレクト
  db.prepare('select sl.severity_jp,sl.severity from alert_levels a,severity_level sl where a.user_id = ? and a.severity_level_id = sl.id  order by sl.severity_level') do |stmt|
    stmt.execute(user_id).each do |ret|
      tmp = {}
      rec_severity_jp = ret[0]
      rec_severity = ret[1]
      tmp[:severity_jp] = rec_severity_jp
      # 送信対象のALASSをセレクト
      tmp[:alass] = get_alass_data(rec_severity, db)
      datas.push(tmp)
    end
  end
  datas
end

def str_format(str, limit,padding)
  # 長い日本語を適当に改行します。
  size = 0
  tmp = ''
  return if str.nil?
  str_tmp = str.split('、').map{|s| if s[(s.length) -1] != '。' then s += '、' else s end }.map{|s| s.split('。')}.flatten.map{|ss| if ss[(ss.length) -1] != '、' then ss += '。'  else ss end}.flatten
  space = ''
  padding.times do 
    space += "　"
  end
  str_tmp[0] = space + str_tmp[0]
  str_tmp.each do |s|
    if s.length > limit
      if size.nonzero?
        tmp = tmp + "\n" + space + s 
        size = s.length
      else
        tmp = tmp + s 
        size = s.length
       end
    else
      size += s.length
      tmp = tmp + s 
    end

    if size > limit
      tmp = tmp + "\n" + space
      size = 0
    end
  end

  tmp
end

    config=YAML.load_file("config.yml")
    mail_from       = config['mail_from']

# データベース接続
database = SQLite3::Database.new('alas.db')

# ユーザテーブルOPEN
rec_user_mail = nil
datas = []
database.transaction do |db|
  # ユーザテーブルselect
  db.prepare('select id,mail from users') do |stmt|
    stmt.execute.each do |ret|
      rec_user_id = ret[0]
      rec_user_mail = ret[1]
      datas = get_data(rec_user_id, db)
      # メールテンプレート展開
      output = ERB.new(open('mail.erb').read, nil, '-').result
      mail = Mail.new do
        from mail_from
        to rec_user_mail
        subject 'Amazon Linux パッチ情報'
        body output
      end
      mail.delivery_method :smtp, {address: "192.168.24.3"}
      mail.deliver
#      open('output.txt', 'w') do |f|
#        f.write(output)
#      end
      #履歴
      send_date = DateTime.now.to_s
      db.prepare('insert into send_histories (user_id,send_date) values (?,?)') do |stmt|
        stmt.execute(rec_user_id,send_date)
      end
    end
  end
end
