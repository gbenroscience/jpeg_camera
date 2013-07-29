supported_flash_version = '9'

if !window.JpegCamera &&
   window.swfobject &&
   swfobject.hasFlashPlayerVersion(supported_flash_version)

  # JpegCamera implementation that uses Flash to capture, display and upload
  # snapshots.
  #
  # @private
  class JpegCameraFlash extends JpegCamera
    # Used by flash object to send message to our instance.
    @_send_message: (id, method) ->
      instance = @_instances[parseInt(id)]

      return unless instance

      args = Array.prototype.slice.call arguments, 2

      @prototype[method].apply instance, args
    @_instances: {}
    @_next_id: 1

    _engine_init: ->
      @_debug "Using Flash engine"

      # register our instance
      @_id = @constructor._next_id++
      @constructor._instances[@_id] = @

      width = @_view_width()
      height = @_view_height()

      if width < 215 || height < 138
        @_got_error "camera is too small to display privacy dialog"
        return

      flash_object_id = "flash_object_" + @_id

      params =
        loop: "false"
        allowScriptAccess: "always"
        allowFullScreen: "false"
        quality: "best"
        wmode: "opaque"
        menu: "false"
      attributes =
        id: flash_object_id
        align: "middle"
      flashvars =
        id: @_id
        width: width
        height: height
        shutter_url: @options.shutter_url
      that = this
      callback = (event) ->
        if !event.success
          that._got_error "Flash loading failed."
        else
          that._debug "Flash loaded"
          that._flash = document.getElementById flash_object_id

      @internal_container = document.createElement "div"
      @internal_container.id = "jpeg_camera_flash_" + @_id
      @internal_container.style.width = "100%"
      @internal_container.style.height = "100%"

      @container.appendChild @internal_container

      swfobject.embedSWF @options.swf_url, @internal_container.id,
        width, height, '9', null, flashvars, params, attributes, callback

    _engine_play_shutter_sound: ->
      @_flash._play_shutter()

    _engine_capture: (snapshot, mirror, quality) ->
      @_flash._capture snapshot.id, mirror, quality

    _engine_display: (snapshot) ->
      @_flash._display snapshot.id

    _engine_discard: (snapshot) ->
      @_flash._discard snapshot.id

    _engine_show_stream: ->
      @_flash._show_stream()

    _engine_upload: (snapshot, api_url, csrf_token, timeout) ->
      @_flash._upload snapshot.id, api_url, csrf_token, timeout

    _flash_prepared: ->
      @_prepared()

    # Called on both - upload success and error
    _flash_upload_complete: (snapshot_id, status_code, error, response) ->
      snapshot_id = parseInt(snapshot_id)
      snapshot = @_snapshots[snapshot_id]

      snapshot._status = parseInt(status_code)
      snapshot._response = response

      if snapshot._status >= 200 && snapshot._status < 300
        snapshot._upload_done()
      else
        snapshot._error_message = error
        snapshot._upload_fail()

  window.JpegCamera = JpegCameraFlash