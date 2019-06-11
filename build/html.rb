#!/usr/bin/env ruby

require 'yaml'
require 'open-uri'
require 'nokogiri'
require 'haml'
require 'ostruct'
require 'fastimage'
require 'fileutils'
require 'json'
require 'active_support/inflector'
require 'active_support/time'

Haml::TempleEngine.options[:attr_wrapper] = '"'

class Template
  def initialize(template)
    @template = File.read template
  end

  def build_page(object, variables = {})
    if object.is_a? Hash
      variables = object
      object = nil
    end
    Haml::Engine.new(@template).to_html(object || Object.new, variables)
  end
end

class Hike
  @@template = Template.new 'templates/hike.haml'
  
  def initialize(yaml, link)
    @link = link
    @id = yaml['id']
    @desc = yaml['desc']
    fetch_info
    fetch_participants
  end

  attr_reader :id, :desc, :full_title, :title, :date, :link
  attr_reader :capacity, :registered, :waiting, :image
  attr_reader :category, :grade, :distance, :ascent

  def url
    hb "/routes/events/#{@id}/"
  end

  def local_link
    "/#{link}/"
  end

  def page_title
    "#{date_string}: #{short_tags.join(' ')} #{title}#{stats && " [#{stats.join(' ')}]"} - Hiking Buddies Munich"
  end

  def date_string
    date.strftime('%-d %b')
  end

  def day_date_string
    date.strftime('%a %-d %b')
  end

  def past?
    date.to_date.past?
  end

  def upcoming?
    not past?
  end

  def time_string
    date.strftime('%H:%M')
  end

  def day_date_time_string
    if DateTime.now.year == date.year
      date.strftime('%a %-d %b, %H:%M')
    elsif past?
      date.strftime('%a %-d %b %Y')
    else
      date.strftime('%a %-d %b %Y, %H:%M')
    end
  end

  def available
    capacity - registered
  end

  def image_height
    fetch_image_info unless instance_variable_defined? :@image_height
    @image_height
  end

  def image_width
    fetch_image_info unless instance_variable_defined? :@image_width
    @image_width
  end

  def short_full_tags
    @tags.map do |tag|
      case tag.downcase
      when 'austria'
        { short: '🇦🇹', full: '🇦🇹 Austria' }
      when 'italy'
        { short: '🇮🇹', full: '🇮🇹 Italy' }
      else
        { short: "[#{tag.titleize}]", full: tag.titleize }
      end
    end
  end

  def tags
    short_full_tags.map { |tag| tag[:full] }
  end

  def short_tags
    short_full_tags.map { |tag| tag[:short] }
  end

  def stats
    (@stats.split(/,\s*/) || []).map { |stat| stat.downcase }
  end

  def category
    @category.name
  end

  def category_icon
    %Q(<i class="fas #{@category.icon}"></i>)
  end

  def save
    html = @@template.build_page(self)

    FileUtils.mkdir_p link
    File.write("#{link}/index.html", html)
  end

  def self.save_indices(hikes)
    template = Template.new('templates/listing.haml')
    save_index(template, 'index.html', hikes.select(&:upcoming?).sort_by(&:date))
    save_index(template, 'past.html', hikes.select(&:past?).sort_by(&:date).reverse)
    save_index(template, 'all.html', hikes.sort_by(&:date).reverse)
  end

  private

  def self.save_index(template, file, hikes)
    html = template.build_page(hikes: hikes, link: "/#{file.sub(/(index)?\.html$/,'')}")
    File.write(file, html)
  end

  def fetch_info
    doc = Nokogiri::HTML source(url)
    
    parse_title_tags doc.at('.event-name').text
    
    rel_image = doc.at('.cover_container')['style'].match(/url\((.+)\)/)[1]
    @image = URI::join(url, rel_image).to_s
    
    date_string = doc.at('input[name=start]')["value"]
    @date = DateTime.strptime(date_string, "%m/%d/%Y %H:%M:%S")

    @capacity = doc.at('input[name=max_participants]')["value"].to_i
  end
  
  def fetch_participants
    json = JSON.parse(source(hb "/routes/get_event_details/?event_id=#{@id}"))
    @registered = JSON.parse(json['participants']).length
    @waiting = JSON.parse(json['participants_waiting']).length
  end
  
  def source(url)
    open(url, 'Accept-Language' => 'en') { |f| f.read }
  end

  def parse_title_tags raw_title
    if (match = raw_title.match(/^(T\d)\s*-\s*(.+)$/))
      @grade = match[1]
      @full_title = match[2]
    else
      @grade = nil
      @full_title = raw_title
    end
    working_title = @full_title
    tags = []
    while (match = working_title.match(/^\[(.+?)\]\s*(.+)$/))
      tags.push(*match[1].split(/,\s*/))
      working_title = match[2]
    end
    if (match = working_title.match(/^(.*\S)\s*\[(.+?)\]$/))
      working_title = match[1]
      parse_stats(match[2])
    end
    @title = working_title
    
    @tags, @category = parse_category(tags)
  end

  def parse_stats(stats)
    stats.split(/,\s*/).each do |stat|
      if (match = stat.match /^(.+[^a-z] km)$/i)
        
        @distance = match[1].strip.downcase
      elsif (match = stat.match /^((.+[^a-z])m)\s+(asc(ent|\.)?|gain)$/i)
        @ascent = match[1].strip.downcase
      else
        STDERR.puts "Unrecognised stat: <#{stat}> [#{stats}]"
      end
    end
  end

  class Category
    def initialize(name, icon, *other_terms)
      @name = name
      @icon = icon
      @terms = other_terms = Set[name.to_s, *other_terms].freeze
    end
  
    attr_reader :name, :icon

    def include? tag
      @terms.nil? or @terms.include? tag
    end
  end

  @@categories = [
    Category.new('cycling', 'fa-biking', 'cycle', 'bike', 'biking'),
    Category.new('hiking', 'fa-hiking', 'hike') # default
  ].freeze

  def parse_category(tags)
    category = nil
    tags = tags.filter { |tag|
      next true if category
      lower_tag = tag.downcase
      category = @@categories.find { |category| category.include? lower_tag }
      false
    }
    return tags, category || @@categories.last
  end

  def hb url
    URI::join('https://www.hiking-buddies.com/', url).to_s
  end

  def fetch_image_info
    @image_width, @image_height = FastImage.size(image)
  end
end

if __FILE__ == $0
  hikes = YAML.load_file('hikes.yml').map do |link, hike|
    hike = Hike.new(hike, link)
    puts "Saving '#{hike.title}' to /#{link}/"
    hike.save
    hike
  end

  Hike.save_indices(hikes)
end
