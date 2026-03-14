;;; qbittorrent.el --- A qBittorrent client -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022 A.I.
;;
;; Author: Merrick Luo <merrick@luois.me>
;; Maintainer: Merrick Luo <merrick@luois.me>
;; Contributors: stardiviner <numbchild@gmail.com>
;; Created: October 07, 2022
;; Modified: October 07, 2022
;; Version: 0.0.1
;; Keywords: files application
;; Homepage: https://github.com/merrickluo/qbittorrent
;; Package-Requires: ((emacs "25.3") (transient "0.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;
;;
;;; Code:

(require 'tabulated-list)
(require 'transient)
(require 'qbittorrent-api)

;;;; Variables

(defvar-local qbittorrent--api-session nil)
(defvar-local qbittorrent--poll-timer nil)

(defvar qbittorrent-buffer "*qBittorrent*")

(defvar qbittorrent-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map "a" 'qbittorrent-dispatch-add)
    (define-key map "q" 'qbittorrent-quit)
    (define-key map "'" 'qbittorrent-dispatch)
    map)
  "Keymap used in the qbittorrent-mode buffer.")

(when (require 'evil nil 'noerror)
  (evil-define-key 'normal qbittorrent-mode-map "a" 'qbittorrent-dispatch-add)
  (evil-define-key 'normal qbittorrent-mode-map "q" 'qbittorrent-quit)
  (evil-define-key 'normal qbittorrent-mode-map "'" 'qbittorrent-dispatch))

;;;; Customization

(defgroup qbittorrent nil
  "Customization options for qbittorrent.el."
  :group 'applications)

(defcustom qbittorrent-baseurl ""
  "The base url of the qBittorrent server, e.g. http://192.168.1.199."
  :type 'string
  :group 'qbittorrent)

(defcustom qbittorrent-username ""
  "Username for the qBittorrent server."
  :type 'string
  :group 'qbittorrent)

(defcustom qbittorrent-password ""
  "Username for the qBittorrent server."
  :type 'string
  :group 'qbittorrent)

(defcustom qbittorrent-refresh-interval 2
  "Torrent list refresh interval in seconds."
  :type 'number
  :group 'qbittorrent)

;;;; Transient menu

(transient-define-prefix qbittorrent-dispatch ()
  "Transient menu for the qbittorrent-mode"
  ["Torrent"
   ["Add"
    ("f" "Add torrent with file" qbittorrent-torrent-add-file)
    ("u" "Add torrent with URL"  qbittorrent-torrent-add-url)]
   ["Info"
    ("P" "Properties" qbittorrent-torrent-properties)
    ("T" "Trackers" qbittorrent-torrent-trackers)
    ("W" "Webseed" qbittorrent-torrent-webseeds)
    ("F" "Files" qbittorrent-torrent-files)]
   ["Actions"
    ("p" "Puase" qbittorrent-torrent-pause)
    ("r" "Resume" qbittorrent-torrent-resume)
    ("D" "Delete" qbittorrent-torrent-delete)]
   ["Priority"
    ("i" "Increase priority" qbittorrent-torrent-increase-priority)
    ("d" "Decrease priority" qbittorrent-torrent-decrease-priority)
    ("m" "Maximal  priority" qbittorrent-torrent-maximal-priority)]]
  ["Transfer"
   ("I" "Info" qbittorrent-transfer-info)
   ("S" "Speed limits mode" qbittorrent-transfer-speed-limits-mode)]
  ["Log"
   ("l" "Logs" qbittorrent-log-main)
   ("p" "Peers" qbittorrent-log-peers)])

;;;;; Transient functions

;;;;;; Add

;; #+begin_example
;; POST /api/v2/torrents/add HTTP/1.1
;; 
;; Content-Type: multipart/form-data; boundary=------WebKitFormBoundaryK83RJd8UOJnwEINW
;; User-Agent: Fiddler
;; Host: 127.0.0.1
;; Cookie: SID=your_sid
;; Content-Length: length
;; 
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="fileselect[]"; filename="kk.torrent"
;; Content-Type: application/octet-stream
;; 
;; 
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="autoTMM"
;; 
;; false
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="savepath"
;; 
;; /downloads
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="rename"
;; 
;; kk
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="category"
;; 
;; 
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="stopped"
;; 
;; false
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="addToTopOfQueue"
;; 
;; true
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="stopCondition"
;; 
;; None
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="contentLayout"
;; 
;; Original
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="firstLastPiecePrio"
;; 
;; true
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="dlLimit"
;; 
;; 0
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW
;; Content-Disposition: form-data; name="upLimit"
;; 
;; 0
;; ------WebKitFormBoundaryK83RJd8UOJnwEINW--
;; #+end_example
;; 

;; TEST
(defun qbittorrent-torrent-add-file (&optional torrent-file)
  "Add TORRENT-FILE to qBittorrent via Web API."
  (interactive "fSelect torrent file: ")
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/add")
         (boundary "------WebKitFormBoundaryUKn3jE4Czae8JlX7")
         (autoTMM (read-string "Torrent 管理模式 (true/false): " "false"))
         (savepath (read-string "Save path: " "/downloads"))
         (rename (read-string "Rename torrent: "))
         (category (read-string "Category: "))
         (stopped (read-string "开始 torrent (true/false): " "false"))
         (addToTopQueue (read-string "添加到队列顶部 (true/false): " "true"))
         (stopCondition (read-string "停止条件: " "None"))
         (contentLayout (read-string "内容布局: " "Original"))
         (dlLimit (read-string "限制下载速率: " "0"))
         (upLimit (read-string "限制上传速率: " "0"))
         (body (string-join
                (list
                 boundary
                 (format "Content-Disposition: form-data; name=\"fileselect[]\"; filename=\"%s\"" (expand-file-name torrent-file))
                 "\n"
                 "Content-Type: application/octet-stream"
                 "\n\n\n"
                 boundary
                 "Content-Disposition: form-data; name=\"autoTMM\""
                 "\n\n"
                 autoTMM
                 boundary
                 "Content-Disposition: form-data; name=\"savepath\""
                 "\n\n"
                 savepath
                 boundary
                 "Content-Disposition: form-data; name=\"rename\""
                 "\n\n"
                 rename
                 boundary
                 "Content-Disposition: form-data; name=\"category\""
                 "\n\n"
                 category
                 boundary
                 "Content-Disposition: form-data; name=\"stopped\""
                 "\n\n"
                 stopped
                 boundary
                 "Content-Disposition: form-data; name=\"addToTopOfQueue\""
                 "\n\n"
                 addToTopQueue
                 boundary
                 "Content-Disposition: form-data; name=\"stopCondition\""
                 "\n\n"
                 stopCondition
                 boundary
                 "Content-Disposition: form-data; name=\"contentLayout\""
                 "\n\n"
                 contentLayout
                 boundary
                 "Content-Disposition: form-data; name=\"dlLimit\""
                 "\n\n"
                 dlLimit
                 boundary
                 "Content-Disposition: form-data; name=\"upLimit\""
                 "\n\n"
                 upLimit
                 boundary)
                "\r\n")))
    (qbittorrent-api session path
                     :method 'post
                     :headers `(("Content-Type" . ,(format "multipart/form-data; boundary=%s" boundary)))
                     :as 'string
                     :body body
                     :then (lambda (_response) (message "Torrent added"))
                     :else #'qbittorrent-api--signal-error)))


;; #+begin_example
;; POST /api/v2/torrents/add HTTP/1.1
;; 
;; User-Agent: Fiddler
;; Host: 127.0.0.1
;; Cookie: SID=your_sid
;; Content-Type: multipart/form-data; boundary=------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Length: length
;; 
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="urls"
;; 
;; magnet:?xt=urn:btih:1057cdf7f8a82fa479077b42d6b2399cde3013d1&dn=%E6%8D%A2%E5%A6%BB.HD1280%E9%AB%98%E6%B8%85%E9%9F%A9%E8%AF%AD%E4%B8%AD%E5%AD%97.mp4
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="autoTMM"
;; 
;; false
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="savepath"
;; 
;; /downloads
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="rename"
;; 
;; 两个妻子 두 아내 (2014)
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="category"
;; 
;; 
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="stopped"
;; 
;; false
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="addToTopOfQueue"
;; 
;; true
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="stopCondition"
;; 
;; None
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="contentLayout"
;; 
;; Original
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="dlLimit"
;; 
;; 0
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7
;; Content-Disposition: form-data; name="upLimit"
;; 
;; 0
;; ------WebKitFormBoundaryUKn3jE4Czae8JlX7--
;; #+end_example
;; 

;; TEST:
(defun qbittorrent-torrent-add-url (&optional torrent-url)
  "Add TORRENT-URL and extra options via multipart/form-data."
  (interactive "sTorrent URL(s): ")
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/add")
         (boundary "------WebKitFormBoundaryUKn3jE4Czae8JlX7")
         (autoTMM (read-string "Torrent 管理模式 (true/false): " "false"))
         (savepath (read-string "Save path: " "/downloads"))
         (rename (read-string "Rename torrent: "))
         (category (read-string "Category: "))
         (stopped (read-string "开始 torrent (true/false): " "false"))
         (addToTopQueue (read-string "添加到队列顶部 (true/false): " "true"))
         (stopCondition (read-string "停止条件: " "None"))
         (contentLayout (read-string "内容布局: " "Original"))
         (dlLimit (read-string "限制下载速率: " "0"))
         (upLimit (read-string "限制上传速率: " "0"))
         (body (string-join
                (list
                 boundary
                 "Content-Disposition: form-data; name=\"urls\""
                 "\n\n"
                 torrent-url
                 boundary
                 "Content-Disposition: form-data; name=\"autoTMM\""
                 "\n\n"
                 autoTMM
                 boundary
                 "Content-Disposition: form-data; name=\"savepath\""
                 "\n\n"
                 savepath
                 boundary
                 "Content-Disposition: form-data; name=\"rename\""
                 "\n\n"
                 rename
                 boundary
                 "Content-Disposition: form-data; name=\"category\""
                 "\n\n"
                 category
                 boundary
                 "Content-Disposition: form-data; name=\"stopped\""
                 "\n\n"
                 stopped
                 boundary
                 "Content-Disposition: form-data; name=\"addToTopOfQueue\""
                 "\n\n"
                 addToTopQueue
                 boundary
                 "Content-Disposition: form-data; name=\"stopCondition\""
                 "\n\n"
                 stopCondition
                 boundary
                 "Content-Disposition: form-data; name=\"contentLayout\""
                 "\n\n"
                 contentLayout
                 boundary
                 "Content-Disposition: form-data; name=\"dlLimit\""
                 "\n\n"
                 dlLimit
                 boundary
                 "Content-Disposition: form-data; name=\"upLimit\""
                 "\n\n"
                 upLimit
                 boundary)
                "\r\n")))
    (qbittorrent-api session path
                     :method 'post
                     :headers `(("Content-Type" . ,(format "multipart/form-data; boundary=%s" boundary)))
                     :as 'string
                     :body body
                     :then (lambda (_response) (message "Torrent added"))
                     :else #'qbittorrent-api--signal-error)))

;;;;;; Torrent

;;;;;;; Torrent Info

(defun qbittorrent-torrent-list ()
  "Show torrent info."
  (interactive)
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/info"))
    (qbittorrent-api session path
                     :then (lambda (valist)
                             (message "Torrent list:\n%S"
                                      (string-join (mapcar (lambda (alist) (cdr (assoc 'name alist))) valist) "\n"))))))

(defun qbittorrent-torrent-properties (&optional torrent-hash)
  "Show torrent properties."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path (format "/api/v2/torrents/properties?hash=%s" torrent-hash)))
    (qbittorrent-api session path
                     :then (lambda (alist) (message "Torrent properties: %s" alist)))))

(defun qbittorrent-torrent-trackers (&optional torrent-hash)
  "Show torrent trackers."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path (format "/api/v2/torrents/trackers?hash=%s" torrent-hash)))
    (qbittorrent-api session path
                     :then (lambda (alist) (message "Torrent trackers: %s" alist)))))

(defun qbittorrent-torrent-webseeds (&optional torrent-hash)
  "Show torrent webseeds."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path (format "/api/v2/torrents/webseeds?hash=%s" torrent-hash)))
    (qbittorrent-api session path
                     :then (lambda (alist) (message "Torrent webseeds: %s" alist)))))

(defun qbittorrent-torrent-files (&optional torrent-hash)
  "Show torrent content files."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path (format "/api/v2/torrents/files?hash=%s" torrent-hash)))
    (qbittorrent-api session path
                     :then (lambda (alist) (message "Torrent content files: %s" alist)))))

;;;;;;; Operations

(defun qbittorrent-torrent-pause (&optional torrent-hash)
  "Pause torrent."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/stop"))
    (qbittorrent-api session path
                     :method 'post
                     :params `(("hashes" ,torrent-hash))
                     :as 'string
                     :then (lambda (response) (message "Paused torrent %s" torrent-hash)))))

(defun qbittorrent-torrent-resume (&optional torrent-hash)
  "Resume torrent."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/start"))
    (qbittorrent-api session path
                     :method 'post
                     :params `(("hashes" ,torrent-hash))
                     :as 'string
                     :then (lambda (response) (message "Resumed torrent %s" torrent-hash)))))

(defun qbittorrent-torrent-delete (&optional torrent-hash)
  "Delete torrent."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/delete"))
    (qbittorrent-api session path
                     :method 'post
                     :params `(("hashes" ,torrent-hash))
                     :as 'string
                     :then (lambda (response) (message "Deleted torrent %s" torrent-hash)))))

;;;;;;; Priority

(defun qbittorrent-torrent-increase-priority (&optional torrent-hash)
  "Increase torrent priority."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/increasePrio"))
    (qbittorrent-api session path
                     :method 'post
                     :params `(("hashes" ,torrent-hash))
                     :as 'string ; response body
                     :then (lambda (response) (message "Increased torrent priority for %s" torrent-hash)))))

(defun qbittorrent-torrent-decrease-priority (&optional torrent-hash)
  "Decrease torrent priority."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/decreasePrio"))
    (qbittorrent-api session path
                     :method 'post
                     :params `(("hashes" ,torrent-hash))
                     :as 'string ; response body
                     :then (lambda (response) (message "Decreased torrent priority for %s" torrent-hash)))))

(defun qbittorrent-torrent-maximal-priority (&optional torrent-hash)
  "Maximal torrent priority."
  (interactive)
  (let* ((torrent-hash (or torrent-hash (tabulated-list-get-id)))
         (session (qbittorrent--ensure-api-session))
         (path "/api/v2/torrents/topPrio"))
    (qbittorrent-api session path
                     :method 'post
                     :params `(("hashes" ,torrent-hash))
                     :as 'string ; response body
                     :then (lambda (response) (message "Maximal torrent priority for %s" torrent-hash)))))

;;;;;; Transfer

(defun qbittorrent-transfer-get-speed-limits-mode ()
  "Get speed limits mode."
  (interactive)
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/transfer/speedLimitsMode")
         (status (qbittorrent-api session path)))
    (if (zerop status) t nil)))

(defun qbittorrent-transfer-info ()
  "Show transfer info."
  (interactive)
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/transfer/info"))
    (qbittorrent-api session path
                     :then (lambda (valist) (message "Transfer info: %S" valist)))))

(defun qbittorrent-transfer-speed-limits-mode ()
  "Toggle speed limits mode."
  (interactive)
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/transfer/toggleSpeedLimitsMode")) ; WARNING: method "toggleSpeedLimitsMode" not allowed.
    (qbittorrent-api session path
                     :then (lambda (valist)
                             (message "Speed Limits Mode %s"
                                      (if (qbittorrent-transfer-get-speed-limits-mode) "enabled" "disabled"))))))

;;;;;; Log

(defun qbittorrent-log-main ()
  "View qbittorrent logs."
  (interactive)
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/log/main?normal=true&info=true&warning=true&critical=true&last_known_id=-1")
         (response (qbittorrent-api session path)))
    (when response
      (let* ((logs (string-join (mapcar (lambda (alist) (cdr (assoc 'message alist))) response) "\n")))
        (with-current-buffer (get-buffer-create "*qBittorrent logs*")
          (let* ((inhibit-read-only t))
            (erase-buffer)
            (insert logs))
          (read-only-mode 1)
          (display-buffer (current-buffer) '(display-buffer-below-selected)))))))

(defun qbittorrent-log-peers ()
  "View qbittorrent peers."
  (interactive)
  (let* ((session (qbittorrent--ensure-api-session))
         (path "/api/v2/log/peers")
         (response (qbittorrent-api session path)))
    (when response
      (let* ((logs (string-join (mapcar (lambda (alist) (cdr (assoc 'reason alist))) response) "\n")))
        (with-current-buffer (get-buffer-create "*qBittorrent peers*")
          (let* ((inhibit-read-only t))
            (erase-buffer)
            (insert logs))
          (read-only-mode 1)
          (display-buffer (current-buffer) '(display-buffer-below-selected)))))))

;;;; tabulated-list-mode

(defun qbittorrent--torrent-eta (torrent)
  "Return human readable eta for TORRENT."
  (let ((eta (alist-get 'eta torrent)))
    (if (= eta 8640000)
        "∞"
      (format-seconds "%Y %D %H %M %z%S" (alist-get 'eta torrent)))))

(defun qbittorrent--torrent-status (torrent)
  "Return human readable status for TORRENT."
  (let* ((state (alist-get 'state torrent)))
    (cond
     ((null state) "")
     ((string-prefix-p "checking" state) "checking")
     ((string-prefix-p "meta" state) "metadata")
     ((string-prefix-p "allocating" state) "allocating")
     ((string-prefix-p "paused" state) "paused")
     ((string-prefix-p "stopped" state) "stopped")
     ((string-prefix-p "queued" state) "queued")
     ((string-prefix-p "stalled" state) "stalled")
     ((string-prefix-p "seeding\\|upload" state) "seeding")
     ((string-prefix-p "downloading\\|download" state) "downloading")
     ((string-prefix-p "error" state) "error")
     (t state))))

(defun qbittorrent--draw-torrents (torrents)
  "Parse the TORRENTS and update tabulated list."
  (when-let* ((buffer (get-buffer qbittorrent-buffer)))
    (with-current-buffer buffer
      ;; (setq-local tabulated-list-format nil)
      (setq-local tabulated-list-use-header-line t)
      (setq-local tabulated-list-entries
                  (cl-map 'list
                          (lambda (torrent)
                            (list (alist-get 'hash torrent) ; for `tabulated-list-get-id'
                                  (vector
                                   ;; Name
                                   (propertize (string-limit (alist-get 'name torrent) 60)
                                               'face '(:foreground "SteelBlue1"))
                                   ;; Size
                                   (propertize (file-size-human-readable (alist-get 'size torrent))
                                               'face '(:foreground "MediumPurple4"))
                                   ;; Done
                                   (propertize (format "%d%%" (* (alist-get 'progress torrent) 100))
                                               'face '(:foreground "yellow4"))
                                   ;; ETA
                                   (propertize (qbittorrent--torrent-eta torrent)
                                               'face '(:foreground "dark gray"))
                                   ;; Download
                                   (propertize (format "%s/s" (file-size-human-readable (alist-get 'dlspeed torrent) nil "" "B"))
                                               'face `(:foreground ,(if (> (alist-get 'dlspeed torrent) 200) "VioletRed1" "dark red")))
                                   ;; Upload
                                   (propertize (format "%s/s" (file-size-human-readable (alist-get 'upspeed torrent) nil "" "B"))
                                               'face '(:foreground "dark green"))
                                   ;; Ratio
                                   (propertize (format "%.2f" (alist-get 'ratio torrent))
                                               'face '(:foreground "purple3"))
                                   ;; Status
                                   (propertize (qbittorrent--torrent-status torrent)
                                               'face '(:foreground "dark cyan"))
                                   ;; Added on
                                   (propertize (format-time-string "%Y-%m-%d %H:%M:%S%p" (alist-get 'added_on torrent))
                                               'face '(:foreground "dark gray")))))
                          torrents))
      (revert-buffer))))

(defvar-local qbittorrent--torrents-info-path "/api/v2/torrents/info?filter=all&sort=added_on&reverse=true"
  "Variable used in list torrents info path for transient sorting & filtering.")

(cl-defun qbittorrent--torrents-info-path-setup (&key (filter "all") (sort "added_on") category tag limit offset reverse)
  "Construct qBittorrent torrents info path API."
  (setq-local qbittorrent--torrents-info-path
              (concat "/api/v2/torrents/info?"
                      (format "filter=%s" filter)
                      (format "&sort=%s" sort)
                      (when category (format "&category=%s" (url-encode-url category)))
                      (when tag (format "&tag=%s" (url-encode-url tag)))
                      (when limit (format "&limit=%d" limit))
                      (when offset (format "&offset=%d" offset))
                      (when reverse (format "&reverse=%s" reverse)))))

(defun qbittorrent--refresh-torrents ()
  "Poll torrents info from server."
  (let ((session (qbittorrent--ensure-api-session))
        (path qbittorrent--torrents-info-path))
    (qbittorrent-api session path :then #'qbittorrent--draw-torrents)))

(define-derived-mode qbittorrent-mode tabulated-list-mode "qBittorrent"
  "Major mode for list of torrents in a qBittorrent server."
  :group 'qbittorrent
  (setq-local line-move-visual nil)
  (setq tabulated-list-padding 1)
  (setq-local tabulated-list-format
              [("Name" 60 t :left-align t)
               ("Size" 8 >= :right-align t)
               ("Done" 8 >= :right-align t)
               ("ETA" 8 >= :right-align t)
               ("Download" 9 nil :right-align t)
               ("Upload" 9 nil :right-align t)
               ("Ratio" 5 >= :right-align t)
               ("Status" 12 t)
               ("Added on" 22 t :left-align t)])
  (setq tabulated-list-revert-hook #'qbittorrent--refresh-torrents)
  (tabulated-list-init-header))

;;;; Commands

;;;###autoload
(defun qbittorrent()
  "Open a `qbittorrent-mode' buffer."
  (interactive)
  (let ((buffer (get-buffer-create qbittorrent-buffer)))
    (with-current-buffer buffer
      (qbittorrent-mode)
      (qbittorrent--refresh-torrents)
      (goto-char (point-min)))
    (switch-to-buffer buffer)))

(defun qbittorrent-quit ()
  "Quit qBittorrent and kill the buffer."
  (interactive)
  (when-let* ((buffer (get-buffer qbittorrent-buffer)))
    (kill-buffer buffer)))

(provide 'qbittorrent)
;;; qbittorrent.el ends here
