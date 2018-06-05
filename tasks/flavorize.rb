require "rake"
require "rake/clean"
require "rdoc/task"
require 'sendgrid-ruby'
require 'nokogiri'
require 'open-uri'

namespace :flavorize do
  include SendGrid

  desc "TO_EMAIL=youremailhere"
  task flavors: :app do
    next if ENV["FROM_EMAIL"].nil? or ENV["TO_EMAIL"].nil? or ENV["SENDGRID_API_KEY"].nil?
    url = "https://www.oscarscustard.com/flavors.html"

    html = Nokogiri::HTML(open(url))

    parents = html.css("span.flavor").map{|x| x.parent.to_s }

    cleaned_parents = parents.map{|x| x.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').gsub(/(<[^>]*>)|\n|\t/s) {" "} }

    days = cleaned_parents.map do |x|
      a = x.strip.split(" ")
      [a.first, a[1..-1].join(" ")]
    end.uniq

    today = Time.now.day

    passed_claw = days.any?{|day, flavor| day.to_i <= today and flavor.downcase.include?("badger claw") }


    # if passed_claw
    #   puts "already passed bclaw"
    #   puts days.inspect
    #   next
    # end

    #'2622259396@vtext.com'
    split_messages = []

    i = 0
    days.map{|x| x.join(" - ") }.each do |mess|

      if !split_messages[i].nil? and split_messages[i].length + mess.length > 120
        i += 1
      end

      split_messages[i] = "" if split_messages[i].nil?

      split_messages[i] = split_messages[i] + "\r\n" + mess
    end

    total = split_messages.count
    split_messages.each_with_index do |message, index|
      i = index + 1
      from = Email.new(email: ENV["FROM_EMAIL"])
      to = Email.new(email: ENV["TO_EMAIL"])
      subject = ""
      content = Content.new(type: 'text/plain', value: "FLAVORS (#{i}/#{total})" + message)
      mail = Mail.new(from, subject, to, content)
      sg = SendGrid::API.new(api_key: ENV["SENDGRID_API_KEY"])

      response = sg.client.mail._('send').post(request_body: mail.to_json)
      puts "sent #{i}/#{total}"
      sleep 20
    end


  end
end