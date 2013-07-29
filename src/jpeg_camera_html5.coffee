navigator.getUserMedia ||=
  navigator.webkitGetUserMedia ||
  navigator.mozGetUserMedia ||
  navigator.msGetUserMedia

if navigator.getUserMedia
  # JpegCamera implementation that uses _getUserMedia_ to capture snapshots,
  # _canvas_element_ to display them, _XHR_ to upload them to the server and
  # optionally _Web_Audio_API_ to play shutter sound.
  #
  # @private
  class JpegCameraHtml5 extends JpegCamera
    # @private
    _engine_init: ->
      @_debug "Using HTML5 engine"

      @internal_container = document.createElement "div"
      @internal_container.style.width = "100%"
      @internal_container.style.height = "100%"
      @internal_container.style.position = "relative"

      @container.appendChild @internal_container

      vertical_padding = Math.floor @_view_height() * 0.2
      horizontal_padding = Math.floor @_view_width() * 0.2

      @message = document.createElement "div"
      @message.class = "message"
      @message.style.width = "100%"
      @message.style.height = "100%"
      @_add_prefixed_style @message, "boxSizing", "border-box"
      @message.style.overflow = "hidden"
      @message.style.textAlign = "center"
      @message.style.paddingTop = "#{vertical_padding}px"
      @message.style.paddingBottom = "#{vertical_padding}px"
      @message.style.paddingLeft = "#{horizontal_padding}px"
      @message.style.paddingRight = "#{horizontal_padding}px"
      @message.style.position = "absolute"
      @message.style.zIndex = 3
      @message.innerHTML =
        "Please allow camera access when prompted by the browser."

      @internal_container.appendChild @message

      @video_container = document.createElement "div"
      @video_container.style.width = "#{@_view_width()}px"
      @video_container.style.height = "#{@_view_height()}px"
      @video_container.style.overflow = "hidden"
      @video_container.style.position = "absolute"
      @video_container.style.zIndex = 1

      @internal_container.appendChild @video_container

      @video = document.createElement 'video'
      @video.autoplay = true
      @_add_prefixed_style @video, "transform", "scalex(-1.0)"

      window.AudioContext ||= window.webkitAudioContext
      @_load_shutter_sound() if window.AudioContext

      get_user_media_options =
        video:
          optional: [
            {minWidth: 1280},
            {minWidth: 640},
            {minWidth: 480},
            {minWidth: 360}
          ]

      that = this

      navigator.getUserMedia get_user_media_options,
        (stream) ->
          that._remove_message()

          if window.URL
            that.video.src = URL.createObjectURL stream
          else
            that.video.src = stream

          that._wait_for_video_ready()
        (error) ->
          # XXX Receives NavigatorUserMediaError object and searches for
          # constant name matching error.code. With the current specification
          # version this will always evaluate to
          # `that._got_error("PERMISSION_DENIED")`.
          code = error.code
          for key, value of error
            continue if key == "code"
            that._got_error key
            return
          that._got_error "UNKNOWN ERROR"

    _engine_play_shutter_sound: ->
      return unless @shutter_buffer

      source = @audio_context.createBufferSource()
      source.buffer = @shutter_buffer
      source.connect @audio_context.destination
      source.start 0

    _engine_capture: (snapshot, mirror, quality) ->
      crop = @_get_capture_crop()

      canvas = document.createElement "canvas"
      canvas.width = crop.width
      canvas.height = crop.height

      context = canvas.getContext "2d"
      context.drawImage @video,
        crop.x_offset, crop.y_offset,
        crop.width, crop.height,
        0, 0,
        crop.width, crop.height

      snapshot._canvas = canvas
      snapshot._mirror = mirror
      snapshot._quality = quality

    _engine_display: (snapshot) ->
      if @displayed_canvas
        @internal_container.removeChild @displayed_canvas

      @displayed_canvas = snapshot._canvas
      @displayed_canvas.style.width = "#{@_view_width()}px"
      @displayed_canvas.style.height = "#{@_view_height()}px"
      @displayed_canvas.style.top = 0
      @displayed_canvas.style.left = 0
      @displayed_canvas.style.position = "absolute"
      @displayed_canvas.style.zIndex = 2
      @_add_prefixed_style @displayed_canvas, "transform", "scalex(-1.0)"

      @internal_container.appendChild @displayed_canvas

    _engine_discard: (snapshot) ->
      if snapshot._xhr
        snapshot._xhr.abort()
      delete snapshot._xhr
      delete snapshot._canvas
      delete snapshot._jpeg_blob

    _engine_show_stream: ->
      if @displayed_canvas
        @internal_container.removeChild @displayed_canvas
        @displayed_canvas = null

      @video_container.style.display = "block"

    _engine_upload: (snapshot, api_url, csrf_token, timeout) ->
      that = this

      if snapshot._jpeg_blob
        @_debug "Uploading the file"

        handler = (event) ->
          delete snapshot._xhr

          snapshot._status = event.target.status
          snapshot._response = event.target.responseText

          if snapshot._status >= 200 && snapshot._status < 300
            snapshot._upload_done()
          else
            snapshot._error_message = event.target.statusText || "Unknown error"
            snapshot._upload_fail()
        xhr = new XMLHttpRequest()
        xhr.open 'POST', api_url
        xhr.timeout = timeout
        xhr.setRequestHeader "X-CSRF-Token", csrf_token if csrf_token
        xhr.onload = handler
        xhr.onerror = handler
        xhr.onabort = handler
        xhr.send snapshot._jpeg_blob

        snapshot._xhr = xhr
      else
        @_debug "Generating JPEG file"

        if snapshot._mirror
          canvas = document.createElement "canvas"
          canvas.width = snapshot._canvas.width
          canvas.height = snapshot._canvas.height

          context = canvas.getContext "2d"
          context.setTransform 1, 0, 0, 1, 0, 0 # reset transformation matrix
          context.translate canvas.width, 0
          context.scale -1, 1
          context.drawImage snapshot._canvas, 0, 0
        else
          canvas = snapshot._canvas

        canvas.toBlob (blob) ->
            snapshot._jpeg_blob = blob
            # call ourselves again with the same parameters
            that._engine_upload snapshot, api_url, csrf_token, timeout
          , "image/jpeg", @quality

    _remove_message: ->
      @message.style.display = "none"

    _load_shutter_sound: ->
      return if @audio_context

      @audio_context = new AudioContext()

      request = new XMLHttpRequest()
      request.open 'GET', @options.shutter_url, true
      request.responseType = 'arraybuffer'

      that = this
      request.onload = ->
        that.audio_context.decodeAudioData request.response, (buffer) ->
          that.shutter_buffer = buffer
      request.send()

    _wait_for_video_ready: ->
      video_width = parseInt @video.videoWidth
      video_height = parseInt @video.videoHeight

      if video_width > 0 && video_height > 0
        @video_container.appendChild @video

        @video_width = video_width
        @video_height = video_height

        @_debug "Camera resolution #{@video_width}x#{@video_height}px"

        crop = @_get_video_crop()

        @video.style.position = "relative"
        @video.style.width = "#{crop.width}px"
        @video.style.height = "#{crop.height}px"
        @video.style.left = "#{crop.x_offset}px"
        @video.style.top = "#{crop.y_offset}px"

        @_prepared()
      else if @_status_checks_count > 100
        @_got_error "Camera failed to initialize in 10 seconds"
      else
        @_status_checks_count++
        that = this
        setTimeout (-> that._wait_for_video_ready()), 100

    _status_checks_count: 0

    _add_prefixed_style: (element, style, value) ->
      uppercase_style = style.charAt(0).toUpperCase() + style.slice(1)
      element.style[style] = value
      element.style["Webkit" + uppercase_style] = value
      element.style["Moz" + uppercase_style] = value
      element.style["ms" + uppercase_style] = value
      element.style["O" + uppercase_style] = value

    _get_video_crop: ->
      view_width = @_view_width()
      view_height = @_view_height()

      video_ratio = @video_width / @video_height
      view_ratio = view_width / view_height

      if video_ratio >= view_ratio
        # fill height, crop width
        @_debug "Filling height"
        video_scale = view_height / @video_height
        scaled_video_width = Math.round @video_width * video_scale

        width: scaled_video_width
        height: view_height
        x_offset: -Math.floor((scaled_video_width - view_width) / 2.0)
        y_offset: 0
      else
        # fill width, crop height
        @_debug "Filling width"
        video_scale = view_width / @video_width
        scaled_video_height = Math.round @video_height * video_scale

        width: view_width
        height: scaled_video_height
        x_offset: 0
        y_offset: -Math.floor((scaled_video_height - view_height) / 2.0)

    _get_capture_crop: ->
      view_width = @_view_width()
      view_height = @_view_height()

      video_ratio = @video_width / @video_height
      view_ratio = view_width / view_height

      if video_ratio >= view_ratio
        # take full height, crop width
        snapshot_width = Math.round @video_height * view_ratio

        width: snapshot_width
        height: @video_height
        x_offset: Math.floor((@video_width - snapshot_width) / 2.0)
        y_offset: 0
      else
        # take full width, crop height
        snapshot_height = Math.round @video_width / view_ratio

        width: @video_width
        height: snapshot_height
        x_offset: 0
        y_offset: Math.floor((@video_height - snapshot_height) / 2.0)

  video_width: null
  video_height: null

  window.JpegCamera = JpegCameraHtml5