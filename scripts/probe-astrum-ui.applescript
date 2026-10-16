on run
  tell application "System Events"
    tell process "Astrum"
      set frontmost to true
      if (count of windows) is 0 then error "Astrum has no accessible window"
      set uiElements to entire contents of window 1
      set signupControl to missing value
      repeat with uiElement in uiElements
        try
          set elementRole to value of attribute "AXRole" of uiElement
          set elementTitle to value of attribute "AXTitle" of uiElement
          if elementTitle is missing value or elementTitle is "" then set elementTitle to value of attribute "AXValue" of uiElement
          if elementRole is "AXButton" and (elementTitle contains "Cadastre-se" or elementTitle contains "Sign up") then
            set signupControl to uiElement
            exit repeat
          end if
        end try
      end repeat
      if signupControl is missing value then error "No accessible sign-up control was found"
      click signupControl
      repeat 20 times
        delay 0.25
        set uiElements to entire contents of window 1
        repeat with uiElement in uiElements
          try
            if (value of attribute "AXRole" of uiElement) is "AXTextField" then
              set originalValue to value of attribute "AXValue" of uiElement
              set value of attribute "AXValue" of uiElement to "qa-ui-probe@example.invalid"
              set probeValue to value of attribute "AXValue" of uiElement
              set value of attribute "AXValue" of uiElement to originalValue
              if probeValue is "qa-ui-probe@example.invalid" then
                return "PROBE_RESULT=interaction_verified; clicked signup and filled/restored an accessible text field"
              end if
            end if
          end try
        end repeat
      end repeat
      error "Sign-up opened, but an accessible text field could not be edited and verified"
    end tell
  end tell
end run
