function __fuzzy-file.fish::check_dependencies
    if not command --query fzf
        set --local reset (set_color normal)
        printf "%s[%s]%s %error:%s %s\n" \
            (set_color blue) "fuzzy-file.fish" $reset \
            (set_color red) $reset \
            "fzf (https://github.com/junegunn/fzf) not installed." >&2
        return 1
    end

    return 0
end


function __fuzzy-file.fish::install --on-event fuzzy-file_install
    # Set universal variables, create bindings, and other initialization logic.
    __fuzzy-file.fish::check_dependencies; or return 1
end

function __fuzzy-file.fish::update --on-event fuzzy-file_update
    # Migrate resources, print warnings, and other update logic.
end

function __fuzzy-file.fish::uninstall --on-event fuzzy-file_uninstall
    # Erase "private" functions, variables, bindings, and other uninstall logic.
end

status is-interactive; or return
__fuzzy-file.fish::check_dependencies; or return 1

function __fuzzy-file.fish::fzf_file_completion
    set --local cmdline (commandline | string trim)
    set --local cursor_position (commandline --cursor)
    set --local token_under_cursor (commandline --current-token)
    # if cmdline is empty, then 99 out of 100 times, I want to pick a file(s)
    # and open it in `nvim`, so `nvim` should be prepended to the commandline
    # If the selected files have an extension, that is not a text file, say .pdf or .png
    # then open them in the default application, with `xdg-open` or 'flatpak-xdg-open'

    # --color="border:#00ffff,header:#ff00ff" \
    set --local fzf_opts \
        --reverse \
        --border-label=" $(string upper "fuzzy-file.fish") " \
        --height="80%" \
        --multi \
        --select-1 \
        --cycle \
        --pointer='|>' \
        --marker='✓ ' \
        --no-mouse \
        --prompt="  select file(s): " \
        --exit-0 \
        --header-first \
        --scroll-off=5 \
        --color='marker:#00ff00' \
        --color="header:#$fish_color_command" \
        --color="info:#$fish_color_keyword" \
        --color="prompt:#$fish_color_autosuggestion" \
        --color='border:#F80069' \
        --color="gutter:-1" \
        --no-scrollbar \
        --bind=ctrl-a:select-all \
        --bind=ctrl-d:preview-page-down \
        --bind=ctrl-u:preview-page-up \
        --bind=ctrl-f:page-down \
        --bind=ctrl-b:page-up \
        --header='The selected file(s) will be inserted at the cursor position' \
        --query="$token_under_cursor"

    # Change layout depending on terminal size
    # 80 is the minimum number of columns, that I want to have.
    # 5 is subtracted, because the border takes up some columns
    # $COLUMNS is divided by 2, because the preview window takes up half the screen width
    if test (math "$COLUMNS / 2") -lt (math '80 - 5')
        set --append fzf_opts --preview-window=down,60%
    else
        set --append fzf_opts --preview-window=right:50%
    end

    # TODO: <kpbaks 2023-06-18 20:30:07> Create a separate script for this e.g. `preview.sh`
    # TODO: <kpbaks 2023-06-18 20:15:53> use `pdftotext {} -` to preview pdf files
    if command --query bat
        # Use bat to preview files
        set --append fzf_opts --preview 'bat --color=always --style=numbers --line-range=:100 {}'
    else if command --query cat
        set --append fzf_opts --preview 'cat --number {}'
    end


    set --local selected_files
    # NOTE: Use `command` to ensure no user defined wrappers are called instead
    if set --query fd
        # Use `fd` if installed to use .gitignore
        set --local fd_opts --type f
        set selected_files (command fd $fd_opts | command fzf $fzf_opts)
    else
        set selected_files (command fzf $fzf_opts)
    end

    for s in $pipestatus
        if test $s -ne 0
            commandline --function repaint
            return $s
        end
    end

    test (count $selected_files) -eq 0; and return 0 # No files selected

    # Sanitize the selected files so the commandline is not broken
    # e.g. if you select a file with a space in it, then the commandline will be broken
    # another example is this file: video_2023-05-25_14-42-09 (trimmed).mp4
    set --local selected_files_sanitized
    for f in $selected_files
        if string match --regex -- '[() ]' $f
            # A pair of () in a file name will be interpreted as a subcommand
            # A space in a file name will be interpreted as a separator between arguments
            set --append selected_files_sanitized "'$f'"
        else
            set --append selected_files_sanitized $f
        end
    end

    # 1. Figure if no program has been specified. If so, check the file extensions
    # of the selected files. If they are all text files, then open them in $EDITOR.
    # If not, then open them in the default application.
    # 2. If a program has been specified, then simply append the selected files to the end of the commandline
    # TODO: <kpbaks 2023-08-31 20:54:36> handle the case where multiple programs are strung together with pipes or ';' or 'or' or 'and'
    set --local program_to_open_files_with
    if test (commandline | string trim) = ""
        if set --query EDITOR
            set program_to_open_files_with $EDITOR
        else if command --query nvim
            set program_to_open_files_with nvim
        else if command --query vim
            set program_to_open_files_with vim
        else
            set program_to_open_files_with nano # eww
        end

        for file in $selected_files_sanitized
            # test -e $file; or continue
            # If a file is a an image file, its mime type will be something like "image/{png,jpeg,webp}"
            # If a files is a video file, its mime type will be something like "video/{mp4,webm}"
            # `file --mime --brief` will return the mime type of a file, e.g. `text/plain` and its encoding, e.g. `charset=utf-8` separated by a `;`
            file --mime --brief $file \
                | string split --fields=1 \; \
                | read --delimiter / type subtype
            if test $type != text
                set program_to_open_files_with open
                if command --query flatpak-xdg-open
                    set program_to_open_files_with flatpak-xdg-open
                else if command --query xdg-open
                    set program_to_open_files_with xdg-open
                end
                break
            end
        end
    end

    if test -n $program_to_open_files_with
        # fish_commandline_prepend $program_to_open_files_with
        commandline --insert "$program_to_open_files_with $selected_files_sanitized "
        # commandline --function execute
    else
        commandline --insert "$selected_files_sanitized "
    end
end

set --query FUZZY_FILE_FISH_KEYBIND; or set --global FUZZY_FILE_FISH_KEYBIND \co
bind "$FUZZY_FILE_FISH_KEYBIND" '__fuzzy-file.fish::fzf_file_completion; commandline --function repaint'
