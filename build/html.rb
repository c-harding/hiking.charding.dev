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

# A HAML template, for rendering a page.
class Template
  # @param [String] template The path to the template, as a HAML file
  def initialize(template)
    @template = Haml::Engine.new(File.read(template))
  end

  # Use the template to generate an html file, with the object and variables
  # provided available in the template.
  #
  # @param [Object] object The object on which methods in the template will
  #   be called.
  # @param [Hash] variables Additional variables accessible in
  #   the template.
  # @return [String] the rendered HTML file
  def build_page(object, variables = {})
    if object.is_a? Hash
      variables = object
      object = nil
    end
    @template.to_html(object || Object.new, variables)
  end
end

class RawEvent
  def initialize(link, id)
    @link, @id = link, id
    fetch_info
    save_info
  end

  FIELDS = [
    :link, :id, :raw_title, :date,
    :image, :image_width, :image_height, :age,
    :capacity, :registered, :waiting,
  ].freeze

  attr_reader(*FIELDS)

  # Has this event happened? Note that this returns false on the day of the
  # event, but true on the following day, even for multiday events.
  #
  # @todo Add support for multiday events, and for determining if the event is
  #   ongoing.
  #
  # @return [Boolean]
  def past?
    date.to_date.past?
  end

  def long_past?
    (date.to_date + 3).past?
  end

  # Is this event yet to happen?
  #
  # @see #past?
  #
  # @return [Boolean]
  def upcoming?
    not past?
  end

  protected

  # Create an absolute URL to the Hiking Buddies website.
  #
  # @param [String] url the relative URL to an item on the HB website.
  #
  # @return [String] an absolute link to +url+.
  def hb url
    URI::join('https://www.hiking-buddies.com/', url).to_s
  end

  # @return [String] the URL to the event on the HB website
  def url
    hb "/routes/events/#{@id}/"
  end

  # @return [String] The contents of the URL, with the language header set to
  # avoid a crash on the Hiking Buddies server.
  def source(url)
    open(url, 'Accept-Language' => 'en') { |f| f.read }
  end

  private

  CACHE_VERSION = 1

  def fetch_info
    fetch_info_cache or fetch_info_web
  end

  def cache_url
    "#{@link}/cache.yml"
  end

  def save_info
    cache = FIELDS.map { |attr|
      [attr, instance_variable_get("@#{attr}")]
    }.to_h

    cache[:version] = CACHE_VERSION
    cache[:long_past] = long_past?

    FileUtils.mkdir_p(@link)
    File.open(cache_url, "w") { |file| file.write(cache.to_yaml) }
  end

  def fetch_info_cache
    no_cache = ENV['TRAVIS_COMMIT_MESSAGE'] =~ /\[no-cache\]/i
    no_cache ||= ENV['TRAVIS_COMMIT_MESSAGE'] =~ /\[no-cache: #{Regexp.escape(@link)}\]/i
    if ENV['REBUILD'] or (ENV['TRAVIS_EVENT_TYPE'] == 'push' and no_cache)
      return false
    end
    begin
      if (base = ENV['URL'])
        cache = YAML::load(source(URI::join(base,cache_url)))
      else
        cache = YAML::load(IO.read(cache_url))
      end
    rescue OpenURI::HTTPError, Errno::ENOENT
      return false
    end
    return false if cache[:id] != @id or cache[:version] != CACHE_VERSION
    FIELDS.each do |attr|
      instance_variable_set("@#{attr}", cache[attr])
    end
    
    @age = cache[:age] + 1
    
    fetch_participants unless cache[:long_past]

    return false if @age > 20 and not past?
    return true
  end

  def fetch_info_web
    puts "#{link}: Fetching from web"
    doc = Nokogiri::HTML(source(url))
    
    @raw_title = doc.at('.event-name').text
    
    rel_image = doc.at('.cover_container')['style'].match(/url\((.+)\)/)[1]
    @image = URI::join(url, rel_image).to_s
    
    date_string = doc.at('input[name=start]')["value"]
    @date = DateTime.strptime(date_string, "%m/%d/%Y %H:%M:%S")

    @capacity = doc.at('input[name=max_participants]')["value"].to_i

    @age = 0

    fetch_participants
  end

  def fetch_image_info
    @image_width, @image_height = FastImage.size(image)
  end

  # Fetch information about the event from the Hiking Buddies Website.
  #
  # This sets {#registered} and {#waiting}, so {#available} can be calculated
  # too.
  def fetch_participants
    puts "#{link}: Fetching participants"
    json = JSON.parse(source(hb "/routes/get_event_details/?event_id=#{@id}"))
    @registered = JSON.parse(json['participants']).length
    @waiting = JSON.parse(json['participants_waiting']).length
  end
end

# An event, used for creating a page for social media previewing, as well as
# for showing up in listings.
class Event < RawEvent
  # The template to use when initialising the event redirect pages.
  HIKE_TEMPLATE = Template.new('templates/event.haml').freeze
  
  # @param [YAML] yaml The description of the event in the events.yml file.
  # @param [String] link The URI component representing this item.
  def initialize(yaml, link)
    super(link, yaml['id'])
    @desc = yaml['desc']
    process_info
  end

  attr_reader :id, :desc, :title, :date, :link
  attr_reader :capacity, :registered, :waiting, :image
  attr_reader :category, :grade, :distance, :ascent

  # @return [String] the relative URL to the event’s page on this site
  def local_link
    "/#{link}/"
  end

  # @return [String] the title attribute for this page, used as a preview in
  #   social media
  def page_title
    "#{date_string}:"\
    "#{[*category_emoji,*short_tags].map { |x| " #{x}" }.join} #{title}"\
    "#{(distance || ascent) && " [#{[distance, "#{ascent} asc."].join(', ')}]"} "\
      "- Hiking Buddies Munich"
  end

  # @return [String] the date of the event, e.g. 4 Jun
  def date_string
    date.strftime('%-d %b')
  end

  # @return [String] the day and date of the event, e.g. Mon 4 Jun
  def day_date_string
    date.strftime('%a %-d %b')
  end

  # @return [String] the time of the event, e.g. 09:30
  def time_string
    date.strftime('%H:%M')
  end

  # @return [String] the date of the event, and additionally the year of the
  #   event if it is not this year, and the time of the event if it is this
  #   year or in the future.
  def day_date_time_string
    if DateTime.now.year == date.year
      date.strftime('%a %-d %b, %H:%M')
    elsif past?
      date.strftime('%a %-d %b %Y')
    else
      date.strftime('%a %-d %b %Y, %H:%M')
    end
  end

  # @return [Integer] the number of spaces still available for the event,
  # ignoring car seat restrictions.
  def available
    capacity - registered
  end

  # Get the height of the header image for the event.
  #
  # @return [Integer]
  def image_height
    @image_height
  end

  # Get the width of the header image for the event.
  #
  # @return [Integer]
  def image_width
    @image_width
  end

  # A pair of representations for an event tag: a {#short} and a {#long} name,
  # for use with the title and alone respectively.
  class Tag
    # @overload initialize(short, long)
    #   @param [<String>] short The {#short} form of the tag.
    #   @param [<String>] long The {#long} form of the tag.
    # 
    # @overload initialize(raw_tag)
    #   Parse the tag from the title to generate the short and long forms.
    #
    #   The long form is the same as extracted, and the short form is not
    #   shortened, but surrounded by square brackets.
    #
    #   @param [<String>] raw_tag The tag originally extracted from the
    #     title, without any processing.
    #
    def initialize(short, long = nil)
      if long.nil?
        initialize("[#{short.titleize}]", short.titleize)
      else
        @short = short.freeze
        @long = long.freeze
      end
    end

    # @return [String] the short form of the tag, safe to be prefixed to a
    #   title.
    attr_reader :short
    # @return [String] the long form of the tag, used in the event preview and
    #   delimited.
    attr_reader :long
  end

  # Get the tags extracted from the event title.
  #
  # @return [Array<Tag>]
  def short_full_tags
    @tags.map do |tag|
      case tag.downcase
      when 'austria' then Tag.new('🇦🇹', '🇦🇹 Austria')
      when 'italy' then Tag.new('🇮🇹', '🇮🇹 Italy')
      else Tag.new(tag)
      end
    end
  end

  # @return [Array<String>] the short form of the tags extracted from the
  #   title, either in emoji/icon form or surrounded with square brackets.
  def tags
    short_full_tags.map(&:long)
  end

  # @return [Array<String>] the long form of the tags extracted from the title
  def short_tags
    short_full_tags.map(&:short)
  end

  # @return [String] the event type, e.g. hiking or biking
  def category
    @category.name
  end

  # @return [String] the category as an icon identifier for FontAwesome
  # @see #category
  def category_emoji
    @category.emoji
  end

  # @return [String] the category as an HTML snippet
  # @see #category
  def category_icon
    @category.html_icon
  end

  # Generate an HTML file for the redirect to the event page for this event,
  # including the metadata for social media, and save it in the location
  # determined by #link.
  #
  # @return [String] the HTML contents of the file.
  def save
    html = HIKE_TEMPLATE.build_page(self)

    FileUtils.mkdir_p(link)
    File.write("#{link}/index.html", html)
    html
  end

  # Generate event redirect pages with social media metadata.
  #
  # Iterate through the events in the +events.yml+ file, and generate the
  # redirect page for it according to the {HIKE_TEMPLATE} template.
  #
  # @return [Array<Event>] The array of {Event +Event+s}, for use in the
  #   indices.
  #
  def self.save_events
    events = YAML.load_file('events.yml').map do |link, event|
      event = Event.new(event, link)
      puts "#{link}: Saving '#{event.title}' to /#{link}/"
      event.save
      event
    end
  end

  private

  # Fetch information about the event from the Hiking Buddies Website.
  #
  # This sets {#image}, {#date} and {#capacity}, as well as everything that
  # {#parse_title_tags} sets.
  #
  # @todo update this
  def process_info
    parse_title_tags(@raw_title)
  end

  # Convert the raw title into tags, stats and the grade.
  #
  # This sets {#grade}, {#tags}, {#category} and {#title}, as well as the
  # stats set by {#parse_stats}.
  def parse_title_tags raw_title
    if (match = raw_title.match(/^(T\d)\s*-\s*(.+)$/))
      @grade = match[1]
      working_title = match[2]
    else
      @grade = nil
      working_title = raw_title
    end
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

  # Extract event statistics from the title.
  #
  # The title usually contains a stats block like +[1.2 Km, 345 m gain]+.
  #
  # This function updates @distance and @ascent.
  #
  # @param [String] stats the raw statistics block contents from the title.
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

  # A container for representing the different categories an event can be,
  # e.g. hiking and biking.
  class Category
    def initialize(*names)
      @name = names.first
      hash = names.last.is_a?(Hash) ? names.pop : {}
      @icon = hash[:icon]
      @emoji = hash[:emoji]
      @terms = Set[*names].freeze
      @used = false
    end
  
    # @return [String] the name of the category
    attr_reader :name

    # @return [String] the FontAwesome icon name
    attr_reader :icon

    # @return [String] the emoji of the category
    attr_reader :emoji

    def used?
      @used
    end

    # @return [String] the category icon as an HTML snippet
    # @see #category
    def html_icon
      if @icon
        %Q(<i class="fas fa-fw #{icon}"></i>)
      else
        @emoji
      end
    end

    # Check if the category has been used at all.
    def include? tag
      return false unless @terms.nil? or @terms.include? tag
      @used = true
      return true
    end
  end

  # The categories that an event can fall under.
  #
  # The first item is the default, for when no other category fits.
  CATEGORIES = [
    Category.new('hiking', 'hike', icon: 'fa-hiking'), # default
    Category.new('cycling', 'cycle', 'bike', 'biking', icon: 'fa-biking', emoji: '🚴‍'),
  ].freeze

  # Search through the tags in the title, extracting the first category tag,
  # or defaulting to the last category in {CATEGORIES}.
  #
  # @param [Array<String>] tags the tags parsed from the title, to scan
  #
  # @return [Array<String>] the unused tags
  # @return [Category] the category found
  def parse_category(tags)
    category = nil
    tags = tags.select { |tag|
      next true if category
      lower_tag = tag.downcase
      category = CATEGORIES.find { |category| category.include? lower_tag }
      next !category
    }
    return tags, category || CATEGORIES.first
  end

  # Fetch the dimensions of the event’s header {#image}.
  #
  # @return [Integer] the *width* of the image in pixels.
  # @return [Integer] the *height* of the image in pixels.
  def fetch_image_info
    @image_width, @image_height = FastImage.size(image)
  end
end

class Listing
  @@template = nil

  def initialize(file, events)
    @file, @events = file, events
  end

  attr_reader :events

  def link
    "/#{@file.sub(/(index)?\.html$/,'')}"
  end

  def save_index
    html = template.build_page(self)
    File.write(@file, html)
  end

  def categories
    return @categories if instance_variable_defined? :@categories
    category_names = events.map(&:category).to_set
    @categories = Event::CATEGORIES.select { |c| category_names.include?(c.name) }
  end

  private
  
  def template
    @@template = @@template || Template.new('templates/listing.haml')
  end

  def self_link?(href)
    href = href.sub(/^\//,'')
    [
      href,
      "#{href}.html",
      href.empty? ? "index.html" : "#{href}/index.html"
    ].include? @file
  end
end

# Create listing pages of the events given, using the +listing.haml+
# template.
#
# Different pages are generated, including for the upcoming and past events.
#
# @param [Array<Event>] events an array of {Event +Event+s} to include.
def save_indices(events)
  listings = [
    Listing.new('index.html', events.select(&:upcoming?).sort_by(&:date)),
    Listing.new('past.html', events.select(&:past?).sort_by(&:date).reverse),
    Listing.new('all.html', events.sort_by(&:date).reverse),
  ]
  listings.each(&:save_index)
end

if __FILE__ == $0
  events = Event.save_events()
  save_indices(events)
end
