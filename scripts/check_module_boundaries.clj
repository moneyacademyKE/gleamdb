#!/usr/bin/env bb
(require '[babashka.fs :as fs]
         '[clojure.edn :as edn]
         '[clojure.string :as str])

(def root (fs/path (or (System/getenv "AARONDB_BOUNDARY_ROOT") ".")))
(def manifest-path (fs/path root "docs/certification/module-boundaries.edn"))

(defn fail [message]
  (binding [*out* *err*] (println (str "embedded-core-v1 boundary: FAIL: " message)))
  (System/exit 1))

(defn read-manifest []
  (edn/read-string (slurp (str manifest-path))))

(defn source-files [manifest layer]
  (map #(fs/path root %)
       (get-in manifest [:layers layer])))

(defn expand-path [path]
  (if (str/ends-with? (str path) "/")
    (filter #(str/ends-with? (str %) ".gleam") (fs/glob path "**/*.gleam"))
    [path]))

(defn imports [path]
  (->> (str/split-lines (slurp (str path)))
       (keep (fn [line]
               (when (str/starts-with? (str/trim line) "import ")
                 (-> line
                     str/trim
                     (str/split #"\s+")
                     second
                     (str/replace #"[.{].*$" "")))))))

(defn forbidden? [prefixes imported]
  (some #(str/starts-with? imported %) prefixes))

(defn approved? [prefixes imported]
  (some #(str/starts-with? imported %) prefixes))

(when-not (fs/regular-file? manifest-path)
  (fail (str "missing manifest " manifest-path)))

(let [manifest (read-manifest)
      forbidden-prefixes (:forbidden-import-prefixes manifest)
      approved-prefixes (:approved-import-prefixes manifest)
      pure-files (mapcat expand-path (source-files manifest :pure))]
  (when (empty? pure-files)
    (fail "manifest has no pure modules"))
  (doseq [path pure-files]
    (when-not (fs/regular-file? path)
      (fail (str "pure module is missing: " path)))
    (doseq [imported (imports path)]
      (cond
        (forbidden? forbidden-prefixes imported)
        (fail (str "pure module " (fs/relativize root path)
                   " imports forbidden runtime boundary '" imported "'"))

        (not (approved? approved-prefixes imported))
        (fail (str "pure module " (fs/relativize root path)
                   " imports unapproved module '" imported "'")))))
  (println (str "EMBEDDED_CORE_BOUNDARIES_OK pure_modules=" (count pure-files))))
