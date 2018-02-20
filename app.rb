# ./app.rb
require "roda"
require 'open-uri'
require 'nokogiri'

class CatApi < Roda
  route do |r|

    r.root do
      "hello"
    end

    r.on "cats" do
      page = (0..2010).to_a.sample
      html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
      img = html.css("img.hatena-fotolife").to_a.sample.attributes["src"].value

      img
    end
  end
end