;;; cricbuzz.el --- Cricket scores from cricbuzz in emacs

;; Copyright (c) 2016 Abhinav Tushar

;; Author: Abhinav Tushar <abhinav.tushar.vs@gmail.com>
;; Version: 0.2
;; Package-Requires: ((enlive "0.0.1"))
;; Keywords: cricket, score
;; URL: https://github.com/lepisma/cricbuzz.el

;;; Commentary:

;; cricbuzz.el displays live cricket scores and match scorecards
;; from http://cricbuzz.com
;; Schedules are saved to ~/cricket-schedule.org and added to org-agenda
;; Visit https://github.com/lepisma/cricbuzz.el for additional information
;; and usage instructions.
;; This file is not a part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'enlive)
(require 'org)

(defvar cricbuzz-base-url "http://cricbuzz.com")
(defvar cricbuzz-live-url (concat cricbuzz-base-url "/cricket-match/live-scores"))
(defvar cricbuzz-schedule-file (expand-file-name "~/cricket-schedule.org"))

(defun replace-str (search replacement str)
  "Replace substring"
  (replace-regexp-in-string (regexp-quote search) replacement str nil 'literal))

;; Parse live scores

(defun cricbuzz-get-url (match-node)
  "Return complete match url"
  (replace-str
   "scores"
   "scorecard"
   (concat cricbuzz-base-url (enlive-attr (enlive-query match-node [a]) 'href))))

(defun cricbuzz-get-time (match-node)
  "Return org time string"
  (format-time-string
   "<%Y-%m-%d %a %H:%M>"
   (seconds-to-time
    (/
     (string-to-number
      (enlive-attr (first (enlive-get-elements-by-class-name match-node "schedule-date")) 'timestamp))
     1000))))

(defun cricbuzz-get-title (match-node)
  "Return match title"
  (enlive-attr (enlive-query match-node [a]) 'title))

(defun cricbuzz-get-properties (match-node)
  "Return description and venue in a list"
  (let ((gray-nodes (enlive-query-all match-node [div.text-gray])))
    (list
     (enlive-text (first gray-nodes))
     (enlive-text (second gray-nodes)))))

(defun cricbuzz-parse-scores (details-node)
  "Return scores of both teams"
  (let ((score-node (enlive-direct-children
                     (first (enlive-query-all details-node [div.text-black])))))
    (list
     (concat
      (enlive-text (first score-node))
      " :: "
      (enlive-text (second score-node)))
     (concat
      (enlive-text (fifth score-node))
      " :: "
      (enlive-text (sixth score-node))))))

(defun cricbuzz-get-status (match-node)
  "Return status, status-text, score-one and score-two"
  (let* ((details-node (second (enlive-query-all match-node [a])))
         (complete-node (first (enlive-get-elements-by-class-name
                                details-node
                                "cb-text-complete")))
         (live-node (first (enlive-get-elements-by-class-name
                            details-node
                            "cb-text-live"))))
    (if live-node
        (cons "LIVE" (cons
                      (enlive-text live-node)
                      (cricbuzz-parse-scores details-node)))
      (if complete-node
          (cons "FINISHED" (cons
                            (enlive-text complete-node)
                            (cricbuzz-parse-scores details-node)))
        (list nil)))))

(defun cricbuzz-insert-match (match-node)
  "Format match node for preview"
  (let ((title (cricbuzz-get-title match-node))
        (time (cricbuzz-get-time match-node))
        (props (cricbuzz-get-properties match-node))
        (url (cricbuzz-get-url match-node))
        (status (cricbuzz-get-status match-node)))
    (insert (concat "* " title "\n"))
    (insert (concat "SCHEDULED: " time "\n"))
    ;; If status is available
    (if (first status)
        (progn
          (org-todo (first status))
          (insert (concat "+ Status :: " (second status) "\n"))
          (insert (concat "+ Scores :: \n"))
          (insert (concat "  + " (third status) "\n"))
          (insert (concat "  + " (fourth status) "\n"))))
    (insert "\n")
    (org-set-property "VENUE" (second props))
    (org-set-property "DESCRIPTION" (first props))
    (org-set-property "URL" (concat "[[" url "][cricbuzz-url]]"))))

;;;###autoload
(defun cricbuzz-get-live-scores ()
  "Display live scores in a buffer"
  (interactive)
  (let ((main-node (first (enlive-get-elements-by-class-name
                           (enlive-fetch cricbuzz-live-url)
                           "cb-schdl")))
        (buffer (get-buffer-create "live cricket scores")))
    (set-buffer buffer)
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert "#+TITLE: Live Cricket Scores\n")
    (insert "#+TODO: LIVE | FINISHED\n\n")
    (insert (format-time-string "Last updated [%Y-%m-%d %a %H:%M] \n"))
    (insert (concat "~scores via [[" cricbuzz-base-url "][cricbuzz]]~\n\n\n"))
    (cricbuzz-index-mode)
    (mapc 'cricbuzz-insert-match
          (enlive-get-elements-by-class-name main-node "cb-mtch-lst"))
    (setq buffer-read-only t)
    (switch-to-buffer buffer)
    (goto-char (point-min))
    ;; Save schedule and add to agenda
    (write-region (point-min) (point-max) cricbuzz-schedule-file)
    (add-to-list 'org-agenda-files cricbuzz-schedule-file)
    (flyspell-mode-off)))

;; Parse scorecard

(defun cricbuzz-insert-scorecard-preamble (match-name match-url match-status)
  "Insert headers for scorecard"
  (insert (concat "#+TITLE: " match-name "\n"))
  (insert (format-time-string "Last updated [%Y-%m-%d %a %H:%M] \n"))
  (insert (concat "~scores via [[" cricbuzz-base-url "][cricbuzz]]~\n"))
  (insert (concat "[[" match-url "][cricbuzz-url]]\n\n\n"))
  (insert (concat "*" (upcase match-status) "*\n\n")))

(defun cricbuzz-insert-match-info (left-node)
  "Insert match info"
  (let ((info-items (enlive-get-elements-by-class-name
                     left-node
                     "cb-mtch-info-itm")))
    (insert "* Match Info \n")
    (mapc #'(lambda (info-item)
              (let ((info-pair (enlive-direct-children info-item)))
                (insert (replace-str " " " " (concat
                                              "+ "
                                              (enlive-text (first info-pair))
                                              " :: "
                                              (enlive-text (second info-pair))
                                              "\n")))))
          info-items)
    (insert "\n")))

(defun cricbuzz-insert-row (row-node)
  "Insert a row of data in table"
  (mapc #'(lambda (row-div)
            (progn
              (org-table-next-field)
              (insert (enlive-text row-div))))
        row-node))

(defun cricbuzz-insert-table (data-nodes)
  "Insert org-table using given data"
  (let* ((header-node (first data-nodes))
         (col-size (length header-node))
         (row-nodes (cdr data-nodes))
         (junk-nodes nil))
    (message (int-to-string col-size))
    (org-table-create (concat (int-to-string col-size) "x1"))
    (cricbuzz-insert-row header-node)
    (org-table-insert-hline t)
    (org-table-next-row)
    (org-table-insert-hline t)
    (mapc #'(lambda (row-node)
              (if (eq col-size (length row-node))
                  (cricbuzz-insert-row row-node)
                (push row-node junk-nodes)))
          row-nodes)
    (org-table-insert-hline)
    (org-table-align)
    (goto-char (point-max))
    (insert "\n")
    ;; Insert junk nodes
    (mapc 'cricbuzz-insert-junk-rows junk-nodes)))

(defun cricbuzz-insert-junk-rows (data-node)
  "Format extra rows in list form"
  (let ((items (mapcar 'enlive-text data-node)))
    (insert (replace-str " " " " (concat "+ " (first items) " :: " (mapconcat
                                                                    'identity
                                                                    (cdr items)
                                                                    " ") "\n")))))

(defun cricbuzz-insert-batting (batting-node)
  "Insert batting card"
  (insert "** Batting\n\n")
  (cricbuzz-insert-table (mapcar 'enlive-direct-children (cdr batting-node))))

(defun cricbuzz-insert-bowling (bowling-node)
  "Insert bowling card"
  (insert "** Bowling\n\n")
  (cricbuzz-insert-table (mapcar 'enlive-direct-children bowling-node)))

(defun cricbuzz-insert-fow (inning-node)
  "Insert fall of wickets if present"
  (if (equal "Fall of Wickets" (enlive-text (second
                                             (enlive-direct-children
                                              inning-node))))
      (progn
        (insert "*** Fall of Wickets\n")
        (insert (replace-str " " " " (concat (enlive-text (third
                                                           (enlive-direct-children
                                                            inning-node))) "\n\n"))))))

(defun cricbuzz-insert-innings (inning-node)
  "Insert an inning"
  (insert (concat "* "
                  (enlive-text (first
                                (enlive-direct-children
                                 (first (enlive-get-elements-by-class-name
                                         inning-node
                                         "cb-scrd-hdr-rw")))))
                  "\n\n"))
  (let ((tables (enlive-get-elements-by-class-name inning-node "cb-ltst-wgt-hdr")))
    (cricbuzz-insert-batting (enlive-direct-children (first tables)))
    (cricbuzz-insert-fow inning-node)
    (cricbuzz-insert-bowling (enlive-direct-children (second tables)))))

(defun cricbuzz-insert-scorecard (match-url)
  "Display scorecard in a buffer"
  (let* ((main-node (enlive-fetch match-url))
         (left-node (first (enlive-get-elements-by-class-name
                            main-node
                            "cb-scrd-lft-col")))
         (match-name (enlive-text (second
                                   (enlive-direct-children
                                    (first
                                     (enlive-get-elements-by-class-name
                                      left-node
                                      "cb-mtch-info-itm"))))))
         (match-status (enlive-text (first (enlive-get-elements-by-class-name
                                           left-node
                                           "cb-scrcrd-status"))))
         (buffer (get-buffer-create match-name)))
    (set-buffer buffer)
    (setq buffer-read-only nil)
    (erase-buffer)
    (cricbuzz-insert-scorecard-preamble match-name match-url match-status)
    (cricbuzz-score-mode)
    (mapc 'cricbuzz-insert-innings
          (butlast (cdr (enlive-direct-children left-node))))
    (cricbuzz-insert-match-info left-node)
    (setq buffer-read-only t)
    (switch-to-buffer buffer)
    (goto-char (point-min))
    (flyspell-mode-off)))

(defun cricbuzz-get-last-url (position)
  "Get last cricbuzz-url searching backward from given position"
  (goto-char position)
  (search-backward "cricbuzz-url")
  ;; Take a margin of 5 chars to get url
  (goto-char (- (match-beginning 0) 5))
  (thing-at-point 'url))

(defun cricbuzz-show-scorecard ()
  "Show scorecard for current match entry"
  (interactive)
  (let ((pos (cdr (org-get-property-block))))
    (if pos
        (cricbuzz-insert-scorecard (cricbuzz-get-last-url pos)))))

(defun cricbuzz-refresh-scorecard ()
  "Refresh current scorecard"
  (interactive)
  (cricbuzz-insert-scorecard (cricbuzz-get-last-url (point))))

(defvar cricbuzz-index-mode-map
  (let ((map (make-keymap)))
    (define-key map (kbd "r") 'cricbuzz-get-live-scores)
    (define-key map (kbd "RET") 'cricbuzz-show-scorecard)
    map)
  "Keymap for cricbuzz-index major mode")

(defvar cricbuzz-score-mode-map
  (let ((map (make-keymap)))
    (define-key map (kbd "r") 'cricbuzz-refresh-scorecard)
    map)
  "Keymap for cricbuzz-index major mode")

(define-derived-mode cricbuzz-index-mode org-mode
  "Cricbuzz-Index"
  "Major mode for cricbuzz live scores")

(define-derived-mode cricbuzz-score-mode org-mode
  "Cricbuzz-Score"
  "Major mode for viewing cricbuzz scorecards")

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.cb\\'" . cricbuzz-score-mode))

(provide 'cricbuzz)

;;; cricbuzz.el ends here
