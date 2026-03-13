;;; qbittorrent-api.el --- An api client for qBittorrent WebUI API -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2022 A.I.
;;
;; Author: Merrick Luo <merrick@luois.me>
;; Maintainer: Merrick Luo <merrick@luois.me>
;; Created: October 07, 2022
;; Modified: October 07, 2022
;; Version: 0.0.1
;; Package-Requires: ((emacs "25.3") (plz "0.2.1"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; API client for qBittorrent WebUI APIs.
;;
;;; Code:

(require 'cl-lib)
(require 'json)
(require 'plz)

(cl-defstruct qbittorrent-api-session
  baseurl cookie)

;;; `plz' :else handler function

(defun qbittorrent-api--signal-error (plz-err)
  "Signal an error for PLZ-ERR.
Borrowed from https://github.com/alphapapa/ement.el"
  (pcase-let* (((cl-struct plz-error response
                           (message plz-message) (curl-error `(,curl-exit-code . ,curl-message)))
                plz-err)
               (status (when (plz-response-p response)
                         (plz-response-status response)))
               (body (when (plz-response-p response)
                       (plz-response-body response)))
               (json-object (when body
                              (ignore-errors
                                (json-read-from-string body))))
               (error-message (format "%S: %s"
                                      (or curl-exit-code status)
                                      (or (when json-object
                                            (alist-get 'error json-object))
                                          curl-message
                                          plz-message))))

    (signal 'qbittorrent-api-error (list error-message))))

;;; login to get session cookie

(defun qbittorrent-api-login (session &optional username password)
  "Login to a qBittorrent instance at SESSION.
USERNAME and PASSWORD can be null if in trusted LAN"
  (let* ((url (format "%s/api/v2/auth/login" (qbittorrent-api-session-baseurl session)))
         (body (format "\nusername=%s&password=%s\n" username password))
         (resp (plz 'post url
                 :headers '(("Content-Type" . "application/x-www-form-urlencoded; charset=utf-8"))
                 :as 'response
                 :body body
                 :else #'qbittorrent-api--signal-error)))
    (when resp
      (let ((set-cookie (alist-get 'set-cookie (plz-response-headers resp))))
        (if set-cookie
            (setf (qbittorrent-api-session-cookie session) (car (string-split set-cookie ";")))
          (error "Login failed, check your username and password"))))
    session))

;;; wrapper for calling API

(cl-defun qbittorrent-api (session path &key method params then else &allow-other-keys)
  "Call qBittorrent API at PATH using SESSION.
Supports :method, :params, :then, :else, and passes other keys to plz."
  (let* ((method (or method 'get))
         (url (concat (qbittorrent-api-session-baseurl session) path))
         (headers `(("Cookie" . ,(qbittorrent-api-session-cookie session))))
         (request-args (list method url :headers headers :as 'json-read)))
    (when params
      (if (eq method 'get)
          (setq url (concat url "?" (url-build-query-string params)))
        (setq request-args (append request-args
                                   (list :body (url-build-query-string params))
                                   (list :headers (append headers '(("Content-Type" . "application/x-www-form-urlencoded"))))))))
    (when then (setq request-args (append request-args (list :then then))))
    (when else (setq request-args (append request-args (list :else else))))
    (apply #'plz request-args)))

;;; Authentication

(defun qbittorrent--ensure-api-session ()
  "Create a new api session if not already created."
  (if qbittorrent--api-session
      qbittorrent--api-session
    (setq qbittorrent--api-session
          (qbittorrent-api-login
           (make-qbittorrent-api-session :baseurl qbittorrent-baseurl)
           qbittorrent-username qbittorrent-password))))

(provide 'qbittorrent-api)
;;; qbittorrent-api.el ends here
