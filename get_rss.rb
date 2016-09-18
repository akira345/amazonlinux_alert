# -*- coding: utf-8 -*-
#
# AmazonLinux RSSチェックスクリプト
# Ruby 2.2.4で作成

require 'pp'
require 'sqlite3'
require 'yaml'
require 'rss'
require 'date'
require 'nokogiri'
require 'mechanize'
require './mstrans.rb'
require 'active_support/all'

class Get_Rss

  def initialize
    @rss_item = {}
    @rss_url = 'https://alas.aws.amazon.com/alas.rss'
    @cve_url = 'https://access.redhat.com/security/cve/'
    # MS翻訳
    @translate = MS_Translator.new

    @agent = Mechanize.new
    @agent.user_agent_alias = 'Windows IE 7'
  end
  def item_parse(item)
    title_parce = item.title.scan(/([\w]+\-[\w]+\-[\w]+) (\(+[\w]+\)): (.*)/).flatten
    @rss_item[:alas_code] = title_parce[0]
    @rss_item[:severity] = title_parce[1].scan(/[\w]+/).flatten[0]
    @rss_item[:packages] = title_parce[2].split(",")
    @rss_item[:cves] = item.description.split(",").map{|c| c.strip}
    @rss_item[:pubdate] = DateTime.parse(item.pubDate.to_s).strftime("%F %X")
    @rss_item[:link] = item.link
  end
  def is_prosess_alas?(alas_code,pubdate,db)
    #処理対象かチェック
    rec_alas_id = nil
    rec_pubdate = nil
    
    db.prepare("select id,pubdate from alass where alas_code = ?") do |stmt|
      stmt.execute(alas_code).each do | ret |
        rec_alas_id = ret[0]
        rec_pubdate = ret[1]
      end
    end
    pp rec_alas_id
    if rec_alas_id.present?
      # 既に登録があるが、日付が異なる場合は更新させる
      if rec_pubdate == pubdate
        #既に登録があるのでスキップ
        return false
      end
    end
    #登録がないか、既に登録があるが日付が異なる場合は処理対象
    return true
  end
  def record_alas(alas_code,pubdate,db)
    #既に登録があるかチェック
    rec_alas_id = nil
    rec_pubdate = nil
    upd_flg = false
    
    db.prepare("select id,pubdate from alass where alas_code = ?") do |stmt|
      stmt.execute(alas_code).each do | ret |
        rec_alas_id = ret[0]
        rec_pubdate = ret[1]
      end
    end
    
    if rec_alas_id.present?
      # 既に登録があるが、日付が異なる場合は更新させる
      if rec_pubdate == pubdate
        #既に登録があるのでスキップ
        return nil
      else
        upd_flg = true
      end
    end

    #ALASのページにアクセスし概要を取得
    get_issue
    if upd_flg
      #削除して登録しなおす。
      db.prepare("delete from alass where id = ?") do |stmt|
        stmt.execute(rec_alas_id)
      end
      db.prepare("insert into alass (id,alas_code,issue_overview,issue_overview_jp,issue_correction,issue_correction_jp,severity,pubdate,link) values (?,?,?,?,?,?,?,?,?)") do |stmt|
        stmt.execute(rec_alas_id,@rss_item[:alas_code],@rss_item[:issue_overview],@rss_item[:issue_overview_jp],
                     @rss_item[:issue_correction],@rss_item[:issue_correction_jp],@rss_item[:severity],@rss_item[:pubdate],@rss_item[:link])
      end
      return rec_alas_id
    else
      #登録
      db.prepare("insert into alass (alas_code,issue_overview,issue_overview_jp,issue_correction,issue_correction_jp,severity,pubdate,link) values (?,?,?,?,?,?,?,?)") do |stmt|
        stmt.execute(@rss_item[:alas_code],@rss_item[:issue_overview],@rss_item[:issue_overview_jp],
          @rss_item[:issue_correction],@rss_item[:issue_correction_jp],@rss_item[:severity],@rss_item[:pubdate],@rss_item[:link])
      end
      return db.last_insert_row_id
    end
  end

  def get_issue
    # ALASの概要を取得し、日本語化する
    @rss_item[:issue_overview] = nil
    @rss_item[:issue_correction] = nil
    @rss_item[:issue_overview_jp] = nil
    @rss_item[:issue_correction_jp] = nil
    if @rss_item[:link].present?
      begin
        # 404など例外は無視。取得できればSet
        @agent.get(@rss_item[:link]) do | page |
          html = Nokogiri::HTML.parse(page.body)
          @rss_item[:issue_overview] =html.xpath('//*[@id="issue_overview"]/p').text
          @rss_item[:issue_correction] =html.xpath('//*[@id="issue_correction"]').text.strip.scan(/^(?!.*Issue Correction:\n).*\.$/).flatten[0].strip
        end
      rescue
        nil
      end
      #取得した概要を日本語訳してみる。
      @rss_item[:issue_overview_jp] = @translate.translate_text(@rss_item[:issue_overview]) if @rss_item[:issue_overview].present?
      @rss_item[:issue_correction_jp] = @translate.translate_text(@rss_item[:issue_correction]) if @rss_item[:issue_correction].present?
    end
  end
  def record_packages(alas_id,packages,db)
    packages.each do |package|
      db.prepare("insert into packages (alas_id,package) values (?,?)") do |stmt|
        stmt.execute(alas_id,package.strip)
      end
    end
  end
  def record_cves(alas_id,cves,db)
    cves.each do |cve|
      redhat_url = File.join(@cve_url, cve)

      cve_details = nil
      cve_details_jp = nil
      # CVEの概要を取得
      begin
        # 404など例外は無視。取得できればSet
        @agent.get(redhat_url) do | page |
          html = Nokogiri::HTML.parse(page.body)
          cve_details = html.xpath('//*[@id="doc"]/div/div/div/div/div/div/div/div/div/div/div[2]/div[1]/div/div').text.strip
        end
      rescue
        nil
      end
      #取得した概要を日本語訳してみる。
      cve_details_jp = @translate.translate_text(cve_details) if cve_details.present?

      db.prepare("insert into cves (alas_id,cve_code,cve_details,cve_details_jp) values (?,?,?,?)") do |stmt|
        stmt.execute(alas_id,cve,cve_details,cve_details_jp)
      end
      # cveのサイトに負荷をかけないようウエイトを入れる。
      sleep(0.5)
    end

  end
  def main
    # データベースOPEN
    database = SQLite3::Database.new("alas.db")

      # RSS受信
      rss = RSS::Parser.parse(@rss_url)
    # トランザクション開始
    database.transaction do |db|
      # DBへ突っ込む
      rss.items.each do |item|
        # タイムアウト設定
        db.busy_timeout(3000)

        #itemをパース
        item_parse(item)
        pp @rss_item[:alas_code]
        #処理対象かチェック
        next if !is_prosess_alas?(@rss_item[:alas_code],@rss_item[:pubdate],db)
        pp "redord"
        #ALASを登録
        alas_id = record_alas(@rss_item[:alas_code],@rss_item[:pubdate],db)
        #更新対象パッケージデータ登録
        record_packages(alas_id,@rss_item[:packages],db)
        #CVE登録
        record_cves(alas_id,@rss_item[:cves],db)
        #コミット
        db.commit
      end
      #履歴
      get_date = DateTime.now.to_s
      db.prepare('insert into rss_get_histories (get_date) values (?)') do |stmt|
        stmt.execute(get_date)
      end
    end
  end
end

get_rss = Get_Rss.new
get_rss.main()


