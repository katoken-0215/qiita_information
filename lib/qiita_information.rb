# coding: utf-8
require "qiita_information/version"

require 'open-uri'
require 'json'

require 'bundler/setup'

require 'capybara/poltergeist'
require 'oga'

Capybara.register_driver :poltergeist do |app|
  Capybara::Poltergeist::Driver.new(app, {:js_errors => false, :timeout => 5 * 60 })
end

module QiitaInformation
  class Item
    def initialize(title, url)
      @title = title
      @url = url
      @document = nil
    end

    def title
      @title
    end

    def url
      @url
    end

    def _internal_parse
      if @document.nil?
        f = open(@url)
        @document = Oga.parse_html(f)
      end
    end

    def _retrieve_like_count_element_from_session(session)
      doc = Nokogiri::HTML.parse(session.html)
      doc.at_css('a.it-Actions_likeCount')
    end

    def like
      session = Capybara::Session.new(:poltergeist)
      result = session.visit(@url)

      if result['status'] == 'fail'
        session.driver.quit
        return like
      end

      like_count_element = nil
      while like_count_element.nil?
        sleep(0.5)
        like_count_element = _retrieve_like_count_element_from_session(session)
      end
      session.driver.quit
      like_count_element.text.to_i
    end

    def hatebu
      f = open("http://api.b.st-hatena.com/entry.counts?url=#{@url}")
      json = JSON.load(f)
      json[@url].to_i
    end

    def date
      _internal_parse

      timeElement = @document.at_css('time[itemprop="dateModified"]') || @document.at_css('time[itemprop="datePublished"]')
      unless timeElement.nil?
        dateString = timeElement.text
      else
        dateString = @document.at_css('.ArticleAsideHeader__date span[data-toggle="tooltip"]').get('title')
      end
      m = /((\d{4})年(\d{1,2})月(\d{1,2})日)|((posted at )?(\d{4})-(\d{1,2})-(\d{1,2}))/.match(dateString)
      if m[1]
        Date.new(m[2].to_i, m[3].to_i, m[4].to_i)
      elsif m[5]
        Date.new(m[7].to_i, m[8].to_i, m[9].to_i)
      end
    end
  end

  class User
    def initialize(name)
      @name = name
    end

    def name
      @name
    end

    def items
      count = 1
      all_items = []
      while true do
        f = open("https://qiita.com/#{@name}?page=#{count}")
        count += 1
        document = Oga.parse_html(f)
        items = document.css('.ItemLink__title a').map do |element|
          title = element.text
          url = element.get('href')
          Item.new(title, "https://qiita.com#{url}")
        end
        if items.empty?
          break
        end
        all_items.concat(items)
      end
      all_items
    end
  end

  class Organization
    def initialize(name)
      @name = name
    end

    def users
      count = 1
      all_items = []
      while true do
        document = Oga.parse_html(open("https://qiita.com/organizations/#{@name}/members?page=#{count}"))
        count += 1
        items = document.css('.organizationMemberList_userName').map do |user|
          User.new(user.text)
        end
        if items.empty?
          break
        end
        all_items.concat(items)
      end
      all_items
    end
  end
end
