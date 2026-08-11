#!/usr/bin/env bb
;; Validate versioned AaronDB evidence against a release SLO profile.
(ns validate-slo-evidence
  (:require [clojure.data.json :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(defn fail! [message]
  (binding [*out* *err*] (println (str "SLO_INVALID " message)))
  (System/exit 1))

(defn read-json [path]
  (try
    (json/read (io/reader path) :key-fn keyword)
    (catch Exception e (fail! (str "invalid-json path=" path " reason=" (.getMessage e))))))

(defn required [m k path]
  (if (contains? m k) (get m k) (fail! (str "missing path=" path "." (name k)))))

(defn at-path [m path]
  (reduce (fn [value k]
            (if (map? value)
              (required value k path)
              (fail! (str "non-map path=" path))))
          m
          (map keyword (str/split path #"\."))))

(defn numeric [m path]
  (let [value (at-path m path)]
    (if (number? value) value (fail! (str "not-number path=" path)))))

(defn compare-thresholds [profile evidence]
  (let [observed (:observed evidence)]
    (->> (:thresholds profile)
         (mapcat (fn [[section limits]]
                   (for [[key limit] limits
                         :let [actual (get-in observed [section key])]
                         :when (or (nil? actual)
                                   (and (str/starts-with? (name key) "min_") (< actual limit))
                                   (and (str/starts-with? (name key) "max_") (> actual limit)))]
                     (if (nil? actual)
                       (str (name section) "." (name key) " missing")
                       (str (name section) "." (name key) " actual=" actual " limit=" limit))))))
         vec)))

(let [[profile-path evidence-path] *command-line-args*]
  (when (or (nil? profile-path) (nil? evidence-path)) (fail! "usage profile.json evidence.json"))
  (let [profile (read-json profile-path)
        evidence (read-json evidence-path)
        _ (when (not= (:profile profile) (required evidence :profile "evidence")) (fail! "profile-mismatch"))
        generated (required evidence :generated_at "evidence")
        generated-ms (.toEpochMilli (java.time.Instant/parse generated))
        age-seconds (/ (- (System/currentTimeMillis) generated-ms) 1000.0)
        max-age (numeric profile "freshness.max_age_seconds")
        _ (when (or (< age-seconds 0) (> age-seconds max-age)) (fail! (str "stale age_seconds=" age-seconds)))
        samples (numeric evidence "samples")
        minimum (numeric profile "assumptions.minimum_samples")
        _ (when (< samples minimum) (fail! (str "under-sampled samples=" samples " minimum=" minimum)))
        violations (compare-thresholds profile evidence)]
    (when (seq violations) (fail! (str/join ";" violations)))
    (println (str "SLO_VALID profile=" (:profile profile) " samples=" samples)))))
