require "gtk2"

require "rabbit/rabbit"
require "rabbit/gettext"

module Rabbit
  module Renderer

    module Base
      include GetText

      def initialize(canvas)
        @canvas = canvas
        @font_families
      end
      
      def font_families
        if @font_families.nil? or @font_families.empty?
          layout = Pango::Layout.new(create_pango_context)
          @font_families = layout.context.list_families
        end
        @font_families
      end

      def print(&block)
        if printable?
          do_print(&block)
        else
          canvas = make_canvas_with_printable_renderer
          pre_print
          Thread.new do
            canvas.print do |i|
              printing(i)
            end
            post_print
          end
        end
      end

      def each_page_pixbuf
        if can_create_pixbuf?
          canvas = @canvas
        else
          canvas = make_canvas_with_offscreen_renderer
        end
        pre_to_pixbuf
        Thread.new do
          canvas.pages.each_with_index do |page, i|
            to_pixbufing(i)
            page.draw(canvas)
            yield(to_pixbuf(page), i)
          end
          post_to_pixbuf
        end
      end
      
      def create_pango_context
        Pango::Context.new
      end
      
      private
      def printable?
        false
      end

      def can_create_pixbuf?
        false
      end
      
      def do_print(&block)
        pre_print
        @canvas.pages.each_with_index do |page, i|
          @canvas.move_to_if_can(i)
          @canvas.current_page.draw(@canvas)
          block.call(i) if block
        end
        post_print
      end

      def make_canvas_with_renderer(renderer)
        canvas = Canvas.new(@canvas.logger, renderer)
        yield canvas
        canvas.apply_theme(@canvas.theme_name)
        @canvas.source_force_modified(true) do |source|
          canvas.parse_rd(source)
        end
        canvas
      end
      
      def make_canvas_with_printable_renderer
        make_canvas_with_renderer(GnomePrint) do |canvas|
        end
      end
      
      def make_canvas_with_offscreen_renderer
        make_canvas_with_renderer(Pixmap) do |canvas|
          canvas.width = @canvas.width
          canvas.height = @canvas.height
        end
      end

    end
    
  end
end