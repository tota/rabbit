require "rabbit/renderer/base"

module Rabbit
  module Renderer
    
    class Pixmap
      include Base

      DEPTH = 24
      
      @@color_table = {}
  
      attr_accessor :width, :height, :pango_context
      
      def initialize(canvas, width=nil, height=nil)
        super(canvas)
        @width = width
        @height = height
        @pango_context = create_pango_context
        init_drawable
        clear_pixmaps
      end

      def has_key?(page)
        @pixmaps.has_key?(page)
      end
      
      def [](page)
        @pixmaps[page]
      end
      
      def foreground=(color)
        @foreground.set_foreground(color)
      end
      
      def background=(color)
        @background.set_foreground(color)
      end
      
      def background_image=(pixbuf)
        w, h = pixbuf.width, pixbuf.height
        pixmap = Gdk::Pixmap.new(nil, w, h, DEPTH)
        pixmap.draw_rectangle(@background, true, 0, 0, w, h)
        args = [
          @foreground, pixbuf,
          0, 0, 0, 0, w, h,
          Gdk::RGB::DITHER_NORMAL, 0, 0,
        ]
        pixmap.draw_pixbuf(*args)
        @background.set_tile(pixmap)
        @background.fill = Gdk::GC::Fill::TILED
      end
      
      def post_apply_theme
        clear_pixmaps
      end

      def post_move(index)
      end

      def post_parse_rd
        clear_pixmaps
      end
      
      def index_mode_on
      end
      
      def index_mode_off
      end
      
      def post_toggle_index_mode
      end
      
      def draw_page(page)
        @drawable = Gdk::Pixmap.new(nil, width, height, DEPTH)
        @pixmaps[page] = @drawable
        @drawable.draw_rectangle(@background, true, 0, 0, width, height)
        yield
      end
      
      def draw_line(x1, y1, x2, y2, color=nil)
        gc = make_gc(color)
        @drawable.draw_line(gc, x1, y1, x2, y2)
      end
      
      def draw_rectangle(filled, x1, y1, x2, y2, color=nil)
        gc = make_gc(color)
        @drawable.draw_rectangle(gc, filled, x1, y1, x2, y2)
      end
      
      def draw_arc(filled, x, y, w, h, a1, a2, color=nil)
        gc = make_gc(color)
        @drawable.draw_arc(gc, filled, x, y, w, h, a1, a2)
      end
      
      def draw_circle(filled, x, y, w, h, color=nil)
        draw_arc(filled, x, y, w, h, 0, 360 * 64, color)
      end
      
      def draw_layout(layout, x, y, color=nil)
        gc = make_gc(color)
        @drawable.draw_layout(gc, x, y, layout)
      end
      
      def draw_pixbuf(pixbuf, x, y, params={})
        gc = make_gc(params['color'])
        args = [0, 0, x, y,
          params['width'] || pixbuf.width,
          params['height'] || pixbuf.height,
          params['dither_mode'] || Gdk::RGB::DITHER_NORMAL,
          params['x_dither'] || 0,
          params['y_dither'] || 0]
        @drawable.draw_pixbuf(gc, pixbuf, *args)
      end
      
      def make_color(color, default_is_foreground=true)
        make_gc(color, default_is_foreground).foreground
      end

      def make_layout(text)
        attrs, text = Pango.parse_markup(text)
        layout = Pango::Layout.new(@pango_context)
        layout.text = text
        layout.set_attributes(attrs)
        w, h = layout.size.collect {|x| x / Pango::SCALE}
        [layout, w, h]
      end

      def to_pixbuf(page)
        drawable = @pixmaps[page]
        args = [drawable.colormap, drawable, 0, 0, width, height]
        Gdk::Pixbuf.from_drawable(*args)
      end

      def clear_pixmaps
        @pixmaps = {}
      end

      def create_pango_context
        Gtk::Invisible.new.create_pango_context
      end
      
      private
      def can_create_pixbuf?
        true
      end
      
      def init_drawable
        @drawable = Gdk::Pixmap.new(nil, 1, 1, DEPTH)
        @foreground = Gdk::GC.new(@drawable)
        @background = Gdk::GC.new(@drawable)
        @background.set_foreground(make_color("white"))
      end
      
      def make_gc(color, default_is_foreground=true)
        if color.nil?
          if default_is_foreground
            @foreground
          else
            @background
          end
        elsif color.is_a?(String)
          make_gc_from_string(color)
        else
          color
        end
      end

      def make_gc_from_string(str)
        gc = Gdk::GC.new(@drawable)
        if @@color_table.has_key?(str)
          color = @@color_table[str]
        else
          color = Gdk::Color.parse(str)
          colormap = Gdk::Colormap.system
          unless colormap.alloc_color(color, false, true)
            raise CantAllocateColorError.new(str)
          end
          @@color_table[str] = color
        end
        gc.set_foreground(color)
        gc
      end

      def pre_to_pixbuf
      end

      def to_pixbufing(i)
      end
      
      def post_to_pixbuf
      end
      
    end
  end
end