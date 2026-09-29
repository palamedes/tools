# frozen_string_literal: true

require 'json'
require 'base64'
require 'fileutils'

# The /screenshots skill's capture harness.
#
# A throwaway feature spec (js: true) requires this file by absolute path,
# includes ScreenshotHarness, builds FAKE test data, visits a page, and calls
# #capture_annotated for each shot. Each call:
#
#   1. fits the browser viewport to the whole page and saves the raw shot
#      (through Chrome's own screenshot command, so nothing is cut off);
#   2. measures every element to highlight, in page coordinates;
#   3. writes the annotator (compose.html, next to this file) beside the raw
#      shot, filled with the header text and the highlights.
#
# After the example body finishes (an after hook this module adds, or an
# explicit #compose_screenshots!), each queued annotator is opened in the same
# headless Chrome and screenshotted as the final PNG: a header band with the
# title and details, a circle or box on each highlight with a numbered badge,
# and numbered callout cards in a right-hand gutter with arrows into the shot.
# Every word a reader needs is drawn into the final image, so it can be pasted
# anywhere on its own. Capturing first and composing last keeps the app page
# (and whatever state the spec put it in) live between shots.
module ScreenshotHarness
  SKILL_DIR = File.expand_path(__dir__)

  # Measures highlight targets in the page as it stands. A block element is
  # measured by what it shows (its children and text, inside its padding), so a
  # box hugs the visible row rather than the element's spacing; inline elements
  # (badges, pills, icons), form controls and fit: 'box' use the element's own
  # box. With all: true a target is the union of every match.
  MEASURE_JS = <<~JS
    (function (specs) {
      function matches(spec) {
        if (spec.xpath || spec.text) {
          var path = spec.xpath || ('//*[text()[contains(normalize-space(.), ' + JSON.stringify(spec.text) + ')]]');
          var scope = spec.within ? document.querySelector(spec.within) : document;
          if (!scope) return [];
          var hits = document.evaluate((spec.within ? '.' : '') + path, scope, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          var nodes = [];
          for (var i = 0; i < hits.snapshotLength; i++) nodes.push(hits.snapshotItem(i));
          return nodes;
        }
        return Array.prototype.slice.call(document.querySelectorAll(spec.selector));
      }
      function measure(el, fit) {
        var box = el.getBoundingClientRect();
        var left = box.left, top = box.top, right = box.right, bottom = box.bottom;
        var hug = fit !== 'box' && window.getComputedStyle(el).display.indexOf('inline') !== 0 &&
                  !/^(img|input|textarea|select|canvas|svg|video|iframe|button)$/i.test(el.tagName);
        if (hug) {
          var range = document.createRange();
          range.selectNodeContents(el);
          var parts = Array.prototype.filter.call(range.getClientRects(), function (r) { return r.width > 0 && r.height > 0; });
          if (parts.length) {
            left = Math.max(box.left, Math.min.apply(null, parts.map(function (r) { return r.left; })));
            top = Math.max(box.top, Math.min.apply(null, parts.map(function (r) { return r.top; })));
            right = Math.min(box.right, Math.max.apply(null, parts.map(function (r) { return r.right; })));
            bottom = Math.min(box.bottom, Math.max.apply(null, parts.map(function (r) { return r.bottom; })));
            if (right <= left || bottom <= top) { left = box.left; top = box.top; right = box.right; bottom = box.bottom; }
          }
        }
        return { x: left + window.scrollX, y: top + window.scrollY, w: right - left, h: bottom - top };
      }
      return specs.map(function (spec) {
        var nodes = matches(spec);
        var boxes = spec.all ? nodes.map(function (el) { return measure(el, spec.fit); }).filter(function (b) { return b.w > 0 || b.h > 0; })
                             : (nodes[spec.index || 0] ? [measure(nodes[spec.index || 0], spec.fit)] : []);
        if (!boxes.length) return null;
        var left = Math.min.apply(null, boxes.map(function (b) { return b.x; }));
        var top = Math.min.apply(null, boxes.map(function (b) { return b.y; }));
        var right = Math.max.apply(null, boxes.map(function (b) { return b.x + b.w; }));
        var bottom = Math.max.apply(null, boxes.map(function (b) { return b.y + b.h; }));
        return { x: Math.round(left), y: Math.round(top), w: Math.round(right - left), h: Math.round(bottom - top) };
      });
    })(arguments[0])
  JS

  def self.included(base)
    base.after { compose_screenshots! } if base.respond_to?(:after)
  end

  # Captures one shot and queues its annotation.
  #
  # @param name       [String] file stem, e.g. "01-goal-story"
  # @param out_dir    [String] where the PNGs land (created if missing)
  # @param title      [String] header title, e.g. "PR #7650 · Goal Story page"
  # @param subtitle   [String, nil] one sentence: what this shot shows
  # @param details    [Array<String>] header pills: branch, date, "Test data · no real patients", ...
  # @param highlights [Array<Hash>] each:
  #   selector: CSS, or xpath:, or text: (an element whose own text contains it)
  #   index: which match (default 0), within: CSS scope for xpath/text,
  #   all: true to box every match together (their union),
  #   fit: :box to frame the element's own box instead of what it shows
  #   label: short bold callout title, note: one or two plain sentences
  #   shape: :box (default), :circle, or :none (arrow only), pad: px around the element (default 6)
  #   arrow: false to draw the shape and badge without a callout card
  # @param clip       [Hash, nil] crop to the part of the page that matters:
  #   { selectors: [CSS or { xpath: } / { text: } target, ...], margin: 48 }
  #   (union of those elements plus margin, the margin fading out), or
  #   { rect: { x:, y:, w:, h: } } in page pixels
  # @param width      [Integer] page width to render at (px)
  # @param max_height [Integer] cap for very long pages (px)
  # @param accent     [String] annotation color
  # @return [String] the final PNG's path (written once the queue is composed)
  def capture_annotated(name:, out_dir:, title:, subtitle: nil, details: [], highlights: [], clip: nil,
                        width: 1440, max_height: 8000, accent: '#e11d48')
    FileUtils.mkdir_p(out_dir)

    fit_viewport(width, 900)
    height = page_height.clamp(600, max_height)
    fit_viewport(width, height)
    page.execute_script('window.scrollTo(0, 0)')
    sleep 0.6
    height = page_height.clamp(600, max_height)

    specs = highlights.map { |h| h.slice(:selector, :xpath, :text, :index, :within, :all, :fit).transform_keys(&:to_s) }
    specs.each { |spec| spec['fit'] = spec['fit'].to_s if spec['fit'] }
    rects = page.evaluate_script(MEASURE_JS, specs)
    missing = highlights.each_with_index.reject { |_, i| rects[i] }.map { |h, _| h[:selector] || h[:xpath] || h[:text] }
    raise "screenshots: highlight target(s) not found on #{page.current_url}: #{missing.join(' | ')}" if missing.any?

    clip_rect, focus_rect = resolve_clip(clip)
    if clip_rect
      outside = highlights.each_with_index.reject { |_, i| overlaps?(rects[i], clip_rect) }.map { |h, _| h[:selector] || h[:xpath] || h[:text] }
      raise "screenshots: highlight(s) outside the clip for #{name}: #{outside.join(' | ')}" if outside.any?
    end
    # The focus is what the crop is for: the clip elements and every highlight.
    # The margin around it fades out, so whatever the crop cuts through reads
    # as context rather than as a broken edge.
    focus_rect &&= clamp_rect(union_rect([focus_rect, *rects.map { |r| r.transform_keys(&:to_sym) }]), clip_rect)
    raw_path  = File.join(out_dir, "#{name}.raw.png")
    chrome_screenshot(raw_path, width: width, height: height)

    config = {
      title: title, subtitle: subtitle, details: details, accent: accent,
      image: File.basename(raw_path), image_width: width, image_height: height, clip: clip_rect, focus: focus_rect,
      highlights: highlights.each_with_index.map do |h, i|
        { label: h[:label], note: h[:note], shape: (h[:shape] || :box).to_s, pad: h.fetch(:pad, 6),
          arrow: h.fetch(:arrow, true), rect: rects[i] }
      end
    }
    compose_path = File.join(out_dir, "#{name}.compose.html")
    template     = File.read(File.join(SKILL_DIR, 'compose.html'))
    File.write(compose_path, template.sub('/*__CONFIG__*/', "window.__SS = #{JSON.generate(config)};"))

    final_path = File.join(out_dir, "#{name}.png")
    (@__screenshot_queue ||= []) << { compose: compose_path, final: final_path }
    final_path
  end

  # Opens each queued annotator and screenshots it. Runs by itself after the
  # example; call it explicitly to compose sooner.
  #
  # @return [Array<String>] the final PNG paths
  def compose_screenshots!
    queue = @__screenshot_queue || []
    @__screenshot_queue = []
    queue.map do |shot|
      page.driver.browser.navigate.to("file://#{shot[:compose]}")
      deadline = Time.now + 15
      sleep 0.2 until page.evaluate_script('window.__SS_DONE === true') || Time.now > deadline
      raise "screenshots: the annotator did not finish: #{shot[:compose]}" unless page.evaluate_script('window.__SS_DONE === true')

      sheet_w, sheet_h = page.evaluate_script('[document.getElementById("sheet").scrollWidth, document.getElementById("sheet").scrollHeight]')
      fit_viewport(sheet_w, sheet_h)
      sleep 0.3
      chrome_screenshot(shot[:final], width: sheet_w, height: sheet_h)
      shot[:final]
    end
  end

  private

  def page_height
    page.evaluate_script('Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)').to_i
  end

  # Sizes the window so the VIEWPORT is width x height: headless Chrome's window
  # includes browser chrome, so the difference is measured and added back.
  def fit_viewport(width, height)
    browser = page.driver.browser
    browser.manage.window.resize_to(width, height)
    sleep 0.3
    inner_w, inner_h = page.evaluate_script('[window.innerWidth, window.innerHeight]')
    return if inner_w == width && inner_h == height

    browser.manage.window.resize_to(width + (width - inner_w), height + (height - inner_h))
    sleep 0.3
  end

  # Chrome's own screenshot of an exact page region, beyond the viewport if need be.
  def chrome_screenshot(path, width:, height:)
    shot = page.driver.browser.execute_cdp('Page.captureScreenshot', format: 'png', captureBeyondViewport: true,
                                                                    clip: { x: 0, y: 0, width: width, height: height, scale: 1 })
    File.binwrite(path, Base64.decode64(shot['data']))
  end

  def overlaps?(rect, clip)
    rect['x'] + rect['w'] > clip[:x] && rect['x'] < clip[:x] + clip[:w] &&
      rect['y'] + rect['h'] > clip[:y] && rect['y'] < clip[:y] + clip[:h]
  end

  # @return [Array(Hash, Hash)] the crop and its focus, each { x:, y:, w:, h: } in
  #   page pixels (both nil for the whole page; no focus for an exact rect)
  def resolve_clip(clip)
    return [nil, nil] if clip.nil?
    return [clip[:rect], nil] if clip[:rect]

    # A crop takes its elements whole, padding and all.
    targets = Array(clip[:selectors] || clip[:selector]).map do |target|
      { 'fit' => 'box' }.merge(target.is_a?(Hash) ? target.transform_keys(&:to_s) : { 'selector' => target })
    end
    rects   = page.evaluate_script(MEASURE_JS, targets)
    missing = targets.each_with_index.reject { |_, i| rects[i] }.map { |t, _| t['selector'] || t['xpath'] || t['text'] }
    raise "screenshots: clip target(s) not found: #{missing.join(' | ')}" if missing.any?

    focus  = union_rect(rects.map { |r| r.transform_keys(&:to_sym) })
    margin = clip.fetch(:margin, 48)
    left   = [focus[:x] - margin, 0].max
    top    = [focus[:y] - margin, 0].max
    right  = focus[:x] + focus[:w] + margin
    bottom = focus[:y] + focus[:h] + margin
    [{ x: left, y: top, w: right - left, h: bottom - top }, focus]
  end

  def union_rect(rects)
    left   = rects.map { |r| r[:x] }.min
    top    = rects.map { |r| r[:y] }.min
    right  = rects.map { |r| r[:x] + r[:w] }.max
    bottom = rects.map { |r| r[:y] + r[:h] }.max
    { x: left, y: top, w: right - left, h: bottom - top }
  end

  def clamp_rect(rect, bounds)
    left   = rect[:x].clamp(bounds[:x], bounds[:x] + bounds[:w])
    top    = rect[:y].clamp(bounds[:y], bounds[:y] + bounds[:h])
    right  = (rect[:x] + rect[:w]).clamp(left, bounds[:x] + bounds[:w])
    bottom = (rect[:y] + rect[:h]).clamp(top, bounds[:y] + bounds[:h])
    { x: left, y: top, w: right - left, h: bottom - top }
  end
end
