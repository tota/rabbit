require 'erb'
require 'fileutils'

begin
  require 'rss/maker'
rescue LoadError
end

require 'rabbit/rabbit'
require 'rabbit/front'
require 'rabbit/utils'
require 'rabbit/keys'

module Rabbit
  module HTML
    class Generator
      include ERB::Util
      public :h

      path = ["rabbit", "html", "template.erb"]
      template_path = Utils.find_path_in_load_path(*path)
      raise CantFindHTMLTemplate.new(File.join(*path)) if template_path.nil?
      erb = File.open(template_path) {|f| ERB.new(f.read, nil, "-")}
      erb.def_method(self, "to_html", template_path)

      def initialize(canvas, base_name, image_type,
                     output_html, output_index_html, rss_base_uri)
        @canvas = canvas
        @suffix = "html"
        @rss_info = []
        @rss_filename = "index.rdf"
        rss_base_uri = rss_base_uri.chomp('/') + '/' if rss_base_uri
        @rss_base_uri = rss_base_uri
        @base_name = base_name
        @base_dir = File.dirname(@base_name)
        @image_type = image_type
        @output_html = output_html
        @output_index_html = output_index_html
        FileUtils.mkdir_p(to_filename_encoding(@base_dir))
      end

      def save
        save_environment do
          @outputting_index = false
          @canvas.each_slide_pixbuf do |slide, pixbuf, slide_number|
            save_slide(slide, pixbuf, slide_number)
            true
          end
          if output_index_html?
            @canvas.with_index_mode(true) do
              @canvas.slides.each_with_index do |slide, slide_number|
                save_index(slide, slide_number)
              end
            end
          end
          unless save_rss
            @canvas.logger.warn(_("can't generate RSS"))
          end
        end
      end
      def save_pixbuf(pixbuf, optional=nil)
        pixbuf.save(pixbuf_filename(@slide_number, optional),
                    normalized_image_type)
        image_src(@slide_number, optional)
      end

      def number_of_places(num)
        n = 1
        target = num
        while target >= 10
          target /= 10
          n += 1
        end
        n
      end

      def output_index_html?
        @output_index_html
      end

      def output_html?
        @output_html
      end

      def output_slide_html?
        output_html? and !@index_mode
      end

      def index_href(slide_number)
        with_outputting_index(true) do
          href(slide_number)
        end
      end

      def slide_href(slide_number)
        with_outputting_index(false) do
          href(slide_number)
        end
      end

      def index_image_title(slide_number)
        @canvas.with_index_mode(true) do
          with_outputting_index(true) do
            image_title(slide_number)
          end
        end
      end

      def slide_image_title(slide_number)
        @canvas.with_index_mode(false) do
          with_outputting_index(false) do
            image_title(slide_number)
          end
        end
      end

      def outputting_index?
        @outputting_index
      end

      def with_outputting_index(index)
        _index = @outputting_index
        @outputting_index = index
        yield
      ensure
        @outputting_index = _index
      end

      private
      def save_environment
        @index_mode = @canvas.index_mode?
        if output_html?
          @canvas.with_index_mode(false) do
            @slide_size = @canvas.slide_size
          end
        end
        if output_index_html?
          @canvas.with_index_mode(true) do
            @index_slide_size = @canvas.slide_size
          end
        end
        yield
      ensure
        @index_mode = nil
        @slide_size = nil
        @index_slide_size = nil
      end

      def save_html(slide, slide_number)
        @slide = slide
        @slide_number = slide_number
        yield
      ensure
        @slide_number = nil
        @slide = nil
      end

      def save_slide(slide, pixbuf, slide_number)
        save_html(slide, slide_number) do
          with_outputting_index(false) do
            save_pixbuf(pixbuf)
            filename = slide_filename
            output_html(filename) if output_html?
            if rss_available?
              @rss_info << [filename, slide_title(slide_number),
                            @slide.to_rd, @slide.to_html(self)]
            end
          end
        end
      end

      def save_index(slide, slide_number)
        save_html(slide, slide_number) do
          with_outputting_index(true) do
            @slide_index_html = @slide.to_html(self)
            filename = slide_filename
            output_html(filename) if output_index_html?
            if rss_available?
              @rss_info << [filename, slide_title(slide_number),
                            @slide.to_rd, @slide_index_html]
            end
            @slide_index_html = nil
          end
        end
      end

      def save_rss
        return true unless rss_available?
        if Object.const_defined?(:RSS)
          rss = make_rss
          name = File.join(@base_dir, @rss_filename)
          File.open(to_filename_encoding(name), "w") do |f|
            f.print(rss.to_s)
          end
          true
        else
          false
        end
      end

      def filename_format
        format = @base_name.dup
        format << "-index" if outputting_index?
        slide_size = outputting_index? ? @index_slide_size : @slide_size
        format << "%0#{number_of_places(slide_size)}d%s.%s"
      end

      def to_filename_encoding(utf8_filename)
        if GLib.respond_to?(:win32_locale_filename_from_utf8)
          GLib.win32_locale_filename_from_utf8(utf8_filename)
        else
          if Utils.windows?
            GLib.locale_from_utf8(utf8_filename)
          else
            GLib.filename_from_utf8(utf8_filename)
          end
        end
      end

      def make_filename(slide_number, suffix, optional=nil, convert=true)
        optional = "-#{optional}" if optional
        name = filename_format % [slide_number, optional || '', suffix]
        if convert
          to_filename_encoding(name)
        else
          name
        end
      end

      def slide_filename(slide_number=@slide_number)
        if !outputting_index? and slide_number.zero?
          File.join(to_filename_encoding(@base_dir), "index.#{@suffix}")
        else
          make_filename(slide_number, @suffix)
        end
      end

      def image_filename(slide_number=@slide_number, optional=nil)
        make_filename(slide_number, @image_type, optional)
      end

      def pixbuf_filename(slide_number=@slide_number, optional=nil)
        make_filename(slide_number, @image_type, optional, !Utils.windows?)
      end

      def output_html(filename)
        File.open(filename, "w") do |f|
          f.print(to_html)
        end
      end

      def normalized_image_type
        case @image_type
        when /jpg/i
          "jpeg"
        else
          @image_type.downcase
        end
      end

      def href(slide_number)
        name = slide_filename(slide_number)
        u(File.basename(name))
      end

      def a_link(slide_number, label, label_only)
        _href = href(slide_number)
        HTML.a_link("<a href=\"#{_href}\">", label, label_only)
      end

      def slide_content
        if outputting_index?
          @slide_index_html
        else
          "<div class=\"slide\">#{slide_image}</div>"
        end
      end

      def image_title(slide_number=@slide_number)
        title = h(slide_title(slide_number))
        title << "(#{slide_number}/#{@canvas.slide_size - 1})"
        title
      end

      def slide_image(slide_number=@slide_number)
        src = image_src(slide_number)
        img = "<img title=\"#{image_title(slide_number)}\" src=\"#{src}\" />"
        if last_slide?(slide_number)
          img
        else
          href = next_href(slide_number)
          "<a href=\"#{href}\">\n#{img}\n</a>"
        end
      end

      def first_slide?(slide_number=@slide_number)
        slide_number.zero?
      end

      def last_slide?(slide_number=@slide_number)
        @canvas.slide_size.zero? or slide_number == @canvas.slide_size - 1
      end

      def first_index(slide_number=@slide_number)
        0
      end

      def previous_index(slide_number=@slide_number)
        slide_number - 1
      end

      def next_index(slide_number=@slide_number)
        slide_number + 1
      end

      def last_index(slide_number=@slide_number)
        @canvas.slide_size - 1
      end

      def first_link(slide_number=@slide_number)
        a_link(first_index(slide_number),
               h("<<"), first_slide?(slide_number))
      end

      def previous_link(slide_number=@slide_number)
        a_link(previous_index(slide_number),
               h("<"), first_slide?(slide_number))
      end

      def next_link(slide_number=@slide_number)
        a_link(next_index(slide_number),
               h(">"), last_slide?(slide_number))
      end

      def last_link(slide_number=@slide_number)
        a_link(last_index(slide_number),
               h(">>"), last_slide?(slide_number))
      end

      def rss_link
        if rss_available?
          attrs = {
            "rel" => "alternate",
            "type" => "application/rss+xml",
            "title" => "RSS",
            "href" => rss_uri,
          }.collect do |key, value|
            "#{h(key)}=\"#{h(value)}\""
          end.join(" ")
          "<link #{attrs} />"
        else
          ''
        end
      end

      def first_href(slide_number=@slide_number)
        href(first_index(slide_number))
      end

      def previous_href(slide_number=@slide_number)
        href(previous_index(slide_number))
      end

      def next_href(slide_number=@slide_number)
        href(next_index(slide_number))
      end

      def last_href(slide_number=@slide_number)
        href(last_index(slide_number))
      end

      def toggle_mode_href
        with_outputting_index(!outputting_index?) do
          first_href
        end
      end

      def toggle_mode_navi
        result = ''
        if outputting_index?
          with_outputting_index(false) do
            result << a_link(first_index, h(_("Slide")), !output_html?)
          end
        else
          with_outputting_index(true) do
            result << a_link(first_index, h(_("Index")), !output_index_html?)
          end
        end
        unless result.empty?
          result = "<div class=\"toggle-mode\">\n#{result}\n</div>"
        end
        result
      end

      def navi(slide_number=@slide_number)
        result = ''
        result << '<div class="navi">'
        result << first_link(slide_number)
        result << previous_link(slide_number)
        result << next_link(slide_number)
        result << last_link(slide_number)
        result << '</div>'
        result
      end

      def image_src(slide_number=@slide_number, optional=nil)
        u(File.basename(image_filename(slide_number, optional)))
      end

      def slide_title(slide_number=@slide_number)
        Utils.unescape_title(@canvas.slide_title(slide_number))
      end

      def rss_available?
        not @rss_base_uri.nil?
      end

      def rss_uri
        "#{@rss_base_uri}#{@rss_filename}"
      end

      def make_rss
        RSS::Maker.make('1.0') do |maker|
          now = Time.now
          title_slide_info = @rss_info.first
          filename, title, text, html = title_slide_info
          maker.channel.about = rss_uri
          maker.channel.title = title
          maker.channel.description = text
          maker.channel.link = @rss_base_uri
          maker.channel.date = now

          @rss_info.each_with_index do |info, i|
            filename, title, text, html = info
            item = maker.items.new_item
            item.link = "#{@rss_base_uri}#{File.basename(filename)}"
            item.title = title
            item.description = text
            item.content_encoded = normalize_html_reference(html, @rss_base_uri)
            item.date = now - i
          end
        end
      end

      def normalize_html_reference(html, base_uri)
        html.gsub(/(href|src)=(["'])((?:(?!\2)[^:])+)\2/) do
          "#{$1}=#{$2}#{base_uri}#{$3}#{$2}"
        end
      end
    end
  end
end
