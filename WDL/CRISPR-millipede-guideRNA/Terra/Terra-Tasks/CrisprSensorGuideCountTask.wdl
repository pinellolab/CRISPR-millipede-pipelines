version development

task CrisprSensorGuideCountTask {
    input {
        String screenId
        File countInputRead1
        File? countInputRead2
        File whitelistGuideReporterTsv
        String? umiToolsHeaderBarcodeRegex
        String? umiToolsUmiPatternRegex
        Int? surrogateHammingThresholdStrict
        Int? barcodeHammingThresholdStrict
        Int? protospacerHammingThresholdStrict

        # Constants for calculating resources
        Int estimatedFastQSpaceMultiplier = 10
        Int estimatedeMemoryBuffer = 2
        Int estimatedDiskGbBuffer = 5
        Int estimatedDockerGbSize = 10
        Int coresPerGbReads = 20

        # Avoid exorbitant resources by setting max resource limit
        Int maxDiskSpaceGB = 500
        Int maxMemoryGB = 50
        Int maxCores = 50

        # Optionally provide explicit resource amounts
        Int? diskGB
        Int? memoryGB
        Int? cpus

        # Provide other resource specifications
        String dockerImage = "pinellolab/crispr_selfedit_mapping:release-0.0.142"
        Int preemptible = 1
        Int maxRetries = 0
        String diskType = "HDD"
    }

    Float fastQSize = size(countInputRead1, "GB") + size(countInputRead2, "GB")
    Int estimatedDiskGB = ceil(estimatedDockerGbSize + fastQSize + (fastQSize * estimatedFastQSpaceMultiplier) + estimatedDiskGbBuffer)
    Int specifiedDiskGB = min(select_first([diskGB, estimatedDiskGB]), maxDiskSpaceGB)
    
    Int estimatedMemoryGB = ceil((fastQSize * estimatedFastQSpaceMultiplier) + estimatedeMemoryBuffer)
    Int specifiedMemoryGB = min(select_first([memoryGB, estimatedMemoryGB]), maxMemoryGB)

    Int estimatedCoresNeeded = ceil(coresPerGbReads * size(countInputRead1, "GB"))
    Int specifiedCores = min(select_first([cpus, estimatedCoresNeeded]), maxCores)


    command <<<
        python <<CODE

        print("Specified Disk (GB): ~{specifiedDiskGB}")
        print("Specified Memory (GB): ~{specifiedMemoryGB}")
        print("Specified Cores: ~{specifiedCores}")
        print("Specified Disk Type: ~{diskType}")
        print("Specified Docker: ~{dockerImage}")

        import crispr_ambiguous_mapping
        import pandas as pd
        
        whitelist_guide_reporter_df = pd.read_table("~{whitelistGuideReporterTsv}")

        result = crispr_ambiguous_mapping.mapping.get_whitelist_reporter_counts_from_umitools_output(
            whitelist_guide_reporter_df=whitelist_guide_reporter_df, 
            fastq_r1_fn='~{countInputRead1}', 
            fastq_r2_fn=~{if defined(countInputRead2) then "'~{countInputRead2}'" else "None" },
            barcode_pattern_regex=~{if defined(umiToolsHeaderBarcodeRegex) then "~{umiToolsHeaderBarcodeRegex}" else "None" },
            umi_pattern_regex=~{if defined(umiToolsUmiPatternRegex) then "~{umiToolsUmiPatternRegex}" else "None" },
            surrogate_hamming_threshold_strict=~{if defined(surrogateHammingThresholdStrict) then "~{surrogateHammingThresholdStrict}" else "None" },
            barcode_hamming_threshold_strict =~{if defined(barcodeHammingThresholdStrict) then "~{barcodeHammingThresholdStrict}" else "None" },
            protospacer_hamming_threshold_strict=~{if defined(protospacerHammingThresholdStrict) then "~{protospacerHammingThresholdStrict}" else "None" },
            cores=~{cpus})

        
        match_set_whitelist_reporter_observed_sequence_counter_series_results = crispr_ambiguous_mapping.processing.get_matchset_alleleseries(result.observed_guide_reporter_umi_counts_inferred, "protospacer_match_surrogate_match_barcode_match", contains_surrogate=result.count_input.contains_surrogate, contains_barcode=result.count_input.contains_barcode, contains_umi=result.count_input.contains_umi) 
        mutations_results = crispr_ambiguous_mapping.processing.get_mutation_profile(match_set_whitelist_reporter_observed_sequence_counter_series_results, whitelist_reporter_df=whitelist_guide_reporter_df, contains_surrogate=result.count_input.contains_surrogate, contains_barcode=result.count_input.contains_barcode) 
        linked_mutation_counters = crispr_ambiguous_mapping.processing.tally_linked_mutation_count_per_sequence(mutations_results=mutations_results, contains_surrogate = result.count_input.contains_surrogate, contains_barcode = result.count_input.contains_barcode)
        crispr_ambiguous_mapping.visualization.plot_mutation_count_histogram(linked_mutation_counters.protospacer_total_mutation_counter, filename="protospacer_total_mutation_histogram.png")
        crispr_ambiguous_mapping.visualization.plot_mutation_count_histogram(linked_mutation_counters.surrogate_total_mutation_counter, filename="surrogate_total_mutation_histogram.png")
        crispr_ambiguous_mapping.visualization.plot_mutation_count_histogram(linked_mutation_counters.barcode_total_mutation_counter, filename="barcode_total_mutation_histogram.png")
        
        with open("protospacer_editing_efficiency.txt", "w") as text_file:
            print(crispr_ambiguous_mapping.utility.calculate_average_editing_frequency(linked_mutation_counters.protospacer_total_mutation_counter), file=text_file)
        with open("surrogate_editing_efficiency.txt", "w") as text_file:
            print(crispr_ambiguous_mapping.utility.calculate_average_editing_frequency(linked_mutation_counters.surrogate_total_mutation_counter), file=text_file)
        with open("barcode_editing_efficiency.txt", "w") as text_file:
            print(crispr_ambiguous_mapping.utility.calculate_average_editing_frequency(linked_mutation_counters.barcode_total_mutation_counter), file=text_file)
            
        crispr_ambiguous_mapping.visualization.plot_trinucleotide_mutational_signature(mutations_results=mutations_results, count_attribute_name="ambiguous_accepted_umi_noncollapsed_mutations", unlinked_mutation_attribute_name = "all_observed_surrogate_unlinked_mutations_df", label='~{screenId}', filename="surrogate_trinucleotide_mutational_signature.png")
        crispr_ambiguous_mapping.visualization.plot_positional_mutational_signature(mutations_results=mutations_results, count_attribute_name="ambiguous_accepted_umi_noncollapsed_mutations", unlinked_mutation_attribute_name = "all_observed_surrogate_unlinked_mutations_df", label='~{screenId}', min_position = 6, max_position=20, filename="surrogate_trinucleotide_positional_signature.png")
        
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "match_set_whitelist_reporter_observed_sequence_counter_series_results", py_object = match_set_whitelist_reporter_observed_sequence_counter_series_results, date_string="")
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "mutations_results", py_object = mutations_results, date_string="")
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "linked_mutation_counters", py_object = linked_mutation_counters, date_string="")
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "whitelist_guide_reporter_df", py_object = whitelist_guide_reporter_df, date_string="")

        
        # Store the complete count result object. This will be a very large object
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "result", py_object = result, date_string="")
        
        # Store the components of the result object, so that the user can load the information as needed
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "count_series_result", py_object = result.all_match_set_whitelist_reporter_counter_series_results, date_string="")
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "observed_guide_reporter_umi_counts_inferred", py_object = result.observed_guide_reporter_umi_counts_inferred, date_string="")
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "quality_control_result", py_object = result.quality_control_result, date_string="")
        crispr_ambiguous_mapping.utility.save_or_load_pickle("./", "count_input", py_object = result.count_input, date_string="")
        
        CODE
    >>>

    output {
        Float protospacer_editing_efficiency =  read_float("protospacer_editing_efficiency.txt")
        Float surrogate_editing_efficiency = read_float("surrogate_editing_efficiency.txt")
        Float barcode_editing_efficiency = read_float("barcode_editing_efficiency.txt")

        File match_set_whitelist_reporter_observed_sequence_counter_series_results = "match_set_whitelist_reporter_observed_sequence_counter_series_results_.pickle"
        File mutations_results = "mutations_results_.pickle"
        File linked_mutation_counters = "linked_mutation_counters_.pickle"

        File protospacer_total_mutation_histogram_pdf = "protospacer_total_mutation_histogram.png"
        File surrogate_total_mutation_histogram_pdf = "surrogate_total_mutation_histogram.png"
        File barcode_total_mutation_histogram_pdf = "barcode_total_mutation_histogram.png"

        File surrogate_trinucleotide_mutational_signature = "surrogate_trinucleotide_mutational_signature.png"
        File surrogate_trinucleotide_positional_signature = "surrogate_trinucleotide_positional_signature.png"

        File whitelist_guide_reporter_df = "whitelist_guide_reporter_df_.pickle"
        File count_result = "result_.pickle"
        File count_series_result = "count_series_result_.pickle"
        File observed_guide_reporter_umi_counts_inferred = "observed_guide_reporter_umi_counts_inferred_.pickle"
        File quality_control_result = "quality_control_result_.pickle"
        File count_input = "count_input_.pickle"
    }

    runtime {
        docker: "${dockerImage}"
        preemptible: "${preemptible}"
        maxRetries: "${maxRetries}"
        memory: "${specifiedMemoryGB} GB"
        disks: "local-disk ${specifiedDiskGB} ${diskType}"
        cpu: "${specifiedCores}"
    }
}