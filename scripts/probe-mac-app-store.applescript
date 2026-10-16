on run
  tell application "System Events"
    if not (exists process "App Store") then error "Mac App Store process is not running"
    tell process "App Store"
      set frontmost to true
      repeat 40 times
        if (count of windows) > 0 then
          set uiElements to entire contents of window 1
          repeat with uiElement in uiElements
            try
              set elementRole to value of attribute "AXRole" of uiElement
              set elementTitle to value of attribute "AXTitle" of uiElement
              if elementTitle is missing value or elementTitle is "" then set elementTitle to value of attribute "AXValue" of uiElement
              if elementRole is "AXButton" and elementTitle is in {"Get", "Download", "Install", "Obter", "Baixar", "Instalar"} then
                click uiElement
                set clickedLabel to elementTitle
                repeat 20 times
                  delay 0.5
                  set uiElements to entire contents of window 1
                  repeat with postClickElement in uiElements
                    try
                      set postClickTitle to value of attribute "AXTitle" of postClickElement
                      if postClickTitle is missing value or postClickTitle is "" then set postClickTitle to value of attribute "AXValue" of postClickElement
                      if postClickTitle contains "Sign In" or postClickTitle contains "Entrar" or postClickTitle contains "Apple ID" then
                        return "APP_STORE_RESULT=apple_id_prompt; control=" & postClickTitle
                      end if
                    end try
                  end repeat
                end repeat
                return "APP_STORE_RESULT=download_button_clicked; label=" & clickedLabel
              end if
            end try
          end repeat
          repeat with uiElement in uiElements
            try
              set elementTitle to value of attribute "AXTitle" of uiElement
              if elementTitle contains "Sign In" or elementTitle contains "Entrar" or elementTitle contains "Apple ID" then
                return "APP_STORE_RESULT=apple_id_prompt; control=" & elementTitle
              end if
            end try
          end repeat
        end if
        delay 0.5
      end repeat
      return "APP_STORE_RESULT=no_accessible_download_button_or_signin_prompt"
    end tell
  end tell
end run
