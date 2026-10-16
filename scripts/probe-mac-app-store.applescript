on run
  tell application "System Events"
    if not (exists process "App Store") then error "Mac App Store process is not running"
    tell process "App Store"
      set frontmost to true
      repeat 20 times
        set observedButtons to {}
        repeat with appWindow in windows
          try
            set buttonControls to buttons of appWindow
          on error
            set buttonControls to {}
          end try
          repeat with buttonControl in buttonControls
            try
              set buttonTitle to value of attribute "AXTitle" of buttonControl
              if buttonTitle is missing value or buttonTitle is "" then set buttonTitle to value of attribute "AXValue" of buttonControl
              if buttonTitle is not missing value then
                set end of observedButtons to buttonTitle as text
                if buttonTitle is in {"Get", "Download", "Install", "Obter", "Baixar", "Instalar"} then
                  click buttonControl
                  return "APP_STORE_RESULT=download_button_clicked; label=" & (buttonTitle as text)
                end if
                if buttonTitle contains "Sign In" or buttonTitle contains "Entrar" or buttonTitle contains "Apple ID" then
                  return "APP_STORE_RESULT=apple_id_prompt; control=" & (buttonTitle as text)
                end if
              end if
            end try
          end repeat
        end repeat
        if (count of observedButtons) > 0 then
          return "APP_STORE_RESULT=buttons_seen_no_download_action; labels=" & (observedButtons as text)
        end if
        delay 0.5
      end repeat
      return "APP_STORE_RESULT=no_accessible_buttons"
    end tell
  end tell
end run
