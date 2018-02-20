# ./app.rb
require "roda"
require 'open-uri'
require 'nokogiri'
require 'easy_translate'

class CatApi < Roda
  route do |r|

    r.root do
      "hello"
    end

    r.on "cats" do
      r.post do
        page = (0..2010).to_a.sample
        html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
        img = html.css("img.hatena-fotolife").to_a.sample.attributes["src"].value

        "<img src=\"#{img}\"></img>"
      end
    end
  end
end