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
(defvar-local qbittorrent--sort-by "added_on")

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
  ["Actions"
   ("a" "Add" qbittorrent-dispatch-add)])

(transient-define-prefix qbittorrent-dispatch-add ()
  "Add new torrent menu for the qbittorrent-mode"
  [("f" "Add new torrent with file" qbittorrent-add-torrent-file)
   ("m" "Add new torrent with magnet" qbittorrent-add-magnet-link)])

;;;; Functions

(defun qbittorrent-add-torrent-file (&optional torrent)
  "Add TORRENT file."
  (interactive)
  (let ((input (read-file-name "Select torrent file: ")))
    (when (file-readable-p input)
      ;; FIXME: do post api implementation
      (message "uploading"))))

(defun qbittorrent-add-magnet-link (&optional link)
  "Add new magnet LINK."
  (interactive)
  (let ((input (read-string "Magnet Link: ")))
    (when (file-readable-p input)
      ;; FIXME: do post api implementation
      (message "uploading"))))

(defun qbittorrent--torrent-eta (torrent)
  "Return human readable eta for TORRENT."
  (let ((eta (alist-get 'eta torrent)))
    (if (= eta 8640000)
        "∞"
      (format-seconds "%Y %D %H %M %z%S" (alist-get 'eta torrent)))))

(defun qbittorrent--torrent-status (torrent)
  "Return human readable status for TORRENT."
  (let ((state (alist-get 'state torrent)))
    (pcase state
      ((or (pred (string-suffix-p "UP")) "uploading") "seeding")
      ((pred (string-suffix-p "DL")) "downloading")
      (_ state))))

(defun qbittorrent--ensure-api-session ()
  "Create a new api session if not already created."
  (if qbittorrent--api-session
      qbittorrent--api-session
    (setq qbittorrent--api-session
          (qbittorrent-api-login
           (make-qbittorrent-api-session :baseurl qbittorrent-baseurl)
           qbittorrent-username qbittorrent-password))))

(defun qbittorrent--draw-torrents (torrents)
  "Parse the TORRENTS and update tabulated list."
  (when-let ((buffer (get-buffer qbittorrent-buffer)))
    (with-current-buffer buffer
      ;; (setq-local tabulated-list-format nil)
      (setq-local tabulated-list-use-header-line t)
      (setq-local tabulated-list-entries
                  (cl-map 'list
                          (lambda (torrent)
                            (list (alist-get 'name torrent)
                                  (vector
                                   ;; Name
                                   (propertize (string-limit (alist-get 'name torrent) 60)
                                               'face '(:foreground "MediumPurple3"))
                                   ;; Size
                                   (propertize (file-size-human-readable (alist-get 'size torrent))
                                               'face '(:foreground "MediumPurple4"))
                                   ;; Done
                                   (propertize (format "%d%%" (* (alist-get 'progress torrent) 100))
                                               'face '(:foreground "yellow3"))
                                   ;; ETA
                                   (propertize (qbittorrent--torrent-eta torrent)
                                               'face '(:foreground "dark gray"))
                                   ;; Download
                                   (propertize (format "%s/s" (file-size-human-readable (alist-get 'dlspeed torrent) nil "" "B"))
                                               'face '(:foreground "dark red"))
                                   ;; Upload
                                   (propertize (format "%s/s" (file-size-human-readable (alist-get 'upspeed torrent) nil "" "B"))
                                               'face '(:foreground "dark green"))
                                   ;; Ratio
                                   (propertize (format "%.2f" (alist-get 'ratio torrent))
                                               'face '(:foreground "purple3"))
                                   ;; Status
                                   (propertize (qbittorrent--torrent-status torrent)
                                               'face '(:foreground "dark orange"))
                                   ;; Added on
                                   (propertize (format-time-string "%Y-%m-%d %H:%M:%S%p" (alist-get 'added_on torrent))
                                               'face '(:foreground "dark gray")))))
                          torrents))
      (revert-buffer))))

(defun qbittorrent--refresh-torrents ()
  "Poll torrents info from server."
  ;; TODO: add sort
  (let ((session (qbittorrent--ensure-api-session)))
    (qbittorrent-api
     session
     (format "/api/v2/torrents/info?sort=%s&reverse=true" qbittorrent--sort-by)
     :then #'qbittorrent--draw-torrents)))

(defun qbittorrent-quit ()
  "Quit qBittorrent and kill the buffer."
  (interactive)
  (when-let ((buffer (get-buffer qbittorrent-buffer)))
    (kill-buffer buffer)))

(define-derived-mode qbittorrent-mode tabulated-list-mode "qBittorrent"
  "Major mode for list of torrents in a qBittorrent server."
  :group 'qbittorrent
  (setq-local line-move-visual nil)
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
  (setq tabulated-list-padding 1)
  (setq tabulated-list-revert-hook #'qbittorrent--refresh-torrents)
  (tabulated-list-init-header))

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

(provide 'qbittorrent)
;;; qbittorrent.el ends here
