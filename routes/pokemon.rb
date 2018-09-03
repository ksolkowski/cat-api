require 'yaml'
require 'ostruct'

class CatApi < Roda
  plugin :path
  path   :pokemon, '/pokemon'
  path   :recipies, '/pokemon/recipies'
  path   :recipie do |recipie|
    "/pokemon/recipies/#{recipie}"
  end

  route('pokemon') do |r|
    ALL_RECIPIES = YAML.load_file("./config/pokemon/recipies.yml").map{|hash| OpenStruct.new(hash.inject({}){|h,(k,v)| h[k.downcase]=v;h }.freeze) }
    sorty = YAML.load_file("./config/pokemon/sort_order.yml").map{|hash| OpenStruct.new(hash.inject({}){|h,(k,v)| h[k.downcase]=v;h }.freeze) }
    available = ALL_RECIPIES.map(&:pokemon).flatten.map{|x| x.split(" - ").first }.
                inject(Hash.new(0)){|h, p| h[p]+=1;h }.sort_by{|name, count| sorty.find{|x| x.name == name }.number.to_i }


    @header = ALL_RECIPIES.map(&:name).uniq.map do |recipie|
      url = recipie_path(recipie.parameterize)
      { name: recipie.humanize, url: url, active: r.path == url }
    end

    def find_recipies(name)
      ALL_RECIPIES.select{|x| x.pokemon.any?{|z| z.include?(name)} }.map do |recipie|
        ingredients = recipie.ingredients
        percent = recipie.pokemon.find{|z| z.include?(name) }.split("-").last.strip
        rarity = recipie.rarity
        OpenStruct.new(rarity: rarity, ingredients: ingredients, percent: percent, name: recipie.name, attracts: recipie.attracts)
      end.sort_by do |r|
        rarity = r.rarity
        if rarity == "Basic"
          0
        elsif rarity == "Good" or rarity.start_with?("Good")
          1
        elsif rarity == "Very Good"
          2
        elsif rarity == "Special"
          3
        else
          4
        end
      end
    end

    r.on "recipies" do
      r.on(:name) do
        @recipies = ALL_RECIPIES.select{|x| x.name.parameterize == r.params["name"] }
        view("pokemon/recipie")
      end

      r.is do
        r.get do
          @recipies = ALL_RECIPIES.map do |recipie|
            name = recipie.name
            {
              "name" => name,
              "attracts" => recipie.attracts,
              "url" => recipie_path(name.parameterize)
            }
          end.uniq
          view("pokemon/recipies")
        end
      end
    end

    r.get do
      @pokemon = available.map do |name, count|
        details = find_recipies(name)
        max_percent = details.max_by{|x| x.percent.gsub("%", "").to_f }.percent
        {"name" => name, "count" => count, "details" => details, "max_percent" => max_percent}
      end

      view("pokemon/index")
    end

  end
end