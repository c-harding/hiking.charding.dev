#!/usr/bin/env ruby

require 'yaml'
require 'open-uri'
require 'nokogiri'
require 'haml'
require 'ostruct'
require 'fastimage'
require 'json'

Haml::TempleEngine.options[:attr_wrapper] = '"'

class Template
  def initialize(template)
    @template = File.read template
  end

  def build_page(properties = {})
    Haml::Engine.new(@template).to_html(OpenStruct.new(properties))
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
  attr_reader :capacity, :registered, :waiting, :image, :grade

  def url
    hb "/routes/events/#{@id}/"
  end

  def local_link
    "/#{link}"
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

  def time_string
    date.strftime('%H:%M')
  end

  def day_date_time_string
    date.strftime('%a %-d %b, %H:%M')
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

  def short_long_tags
    @tags.flat_map { |tag| tag.split(/,\s*/) }.map do |tag|
      case tag.downcase
      when 'cycle', 'cycling', 'bike', 'biking'
        { short: '🚲', full: '🚲 Cycling' }
      else
        { short: "[#{tag.titleize}]", full: tag.titleize }
      end
    end
  end

  def tags
    short_long_tags.map { |tag| tag[:full] }
  end

  def short_tags
    short_long_tags.map { |tag| tag[:short] }
  end

  def stats
    (@stats.split(/,\s*/) || []).map { |stat| stat.downcase }
  end

  def save
    html = @@template.build_page(
      canonical_link: "/#{link}",
      url: url, title: page_title,
      image: image, image_width: image_width, image_height: image_height)
    File.write("#{link}.html", html)
  end

  def self.save_index(hikes)
    template = Template.new('templates/listing.haml')
    html = template.build_page(hikes: hikes.sort_by(&:date))
    File.write('index.html', html)
  end

  private

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
      tags << match[1]
      working_title = match[2]
    end
    if (match = working_title.match(/^(.+)\s*\[(.+?)\]$/))
      working_title = match[1]
      @stats = match[2]
    else
      @stats = nil
    end
    @title = working_title
    @tags = tags
    return @title, @tags
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
    raise 'Cannot overwrite index' if link == 'index'
    hike = Hike.new(hike, link)
    hike.save
    hike
  end

  Hike.save_index(hikes)
end
