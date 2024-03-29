version development

import "https://api.firecloud.org/ga4gh/v1/tools/pinellolab:BBMapDemultiplexOrchestratorWorkflow/versions/6/plain-WDL/descriptor" as demultiplex
import "https://api.firecloud.org/ga4gh/v1/tools/pinellolab:CrisprSensorGuideCountTask/versions/2/plain-WDL/descriptor" as count

workflow CrisprSelfEditMappingOrchestratorWorkflow {
    input {
        # TASK PARAMS
        Map[String, Array[Pair[AnnotatedSample, Array[String]]]] input_screenIdToSampleMap

        File? input_whitelistGuideReporterTsv
        Map[String, File]? input_screenIdToWhitelistGuideReporterTsv
        Map[String, File]? input_screenIdToGuideAnnotationsTsv

        String? input_umiToolsHeaderBarcodeRegex
        String? input_umiToolsUmiPatternRegex
        
        Int? input_surrogateHammingThresholdStrict
        Int? input_barcodeHammingThresholdStrict
        Int? input_protospacerHammingThresholdStrict


        # RUNTIME PARAMS
        String dockerImage = "pinellolab/crispr_selfedit_mapping:release-0.0.142"
        Int preemptible = 1
        Int diskGB = 10
        Int memoryGB = 2
        Int maxRetries = 0
        String diskType = "HDD"
        Int cpus = 1
    }

    #
    #   IMPORTANT NOTE: If input_whitelistGuideReporterTsv is provided but not input_screenIdToWhitelistGuideReporterTsv (i.e. same guide table for all samples), then workflow will fail. Will end up with duplicate code, but use if statement to do happy and exception path.
    #
    # Iterate through all screenId-sample pairs
    scatter(input_screenIdToSamplePair in as_pairs(input_screenIdToSampleMap)){
        String screenId = input_screenIdToSamplePair.left
        Array[Pair[AnnotatedSample,Array[String]]] screenAnnotatedSamples = input_screenIdToSamplePair.right
        
        if(screenId != "None"){
            # Iterate through each saple of the screen ID
            scatter(annotatedSamplePair in screenAnnotatedSamples){
                AnnotatedSample annotatedSample = annotatedSamplePair.left
                Array[String] sampleInfoVars = annotatedSamplePair.right

                # Select the whitelist guide reporter TSV to use for mapping
                Map[String, File] input_screenIdToWhitelistGuideReporterTsv_defined = select_first([input_screenIdToWhitelistGuideReporterTsv])
                File screen_whitelistGuideReporterTsv = input_screenIdToWhitelistGuideReporterTsv_defined[screenId]
                
                #
                #   Perform guide mapping of sample
                #
                call count.CrisprSensorGuideCountTask as GuideCount_ScreenId {
                    input:
                        screenId=screenId,
                        countInputRead1=annotatedSample.read1,
                        countInputRead2=annotatedSample.read2,
                        whitelistGuideReporterTsv=screen_whitelistGuideReporterTsv,
                        umiToolsHeaderBarcodeRegex=input_umiToolsHeaderBarcodeRegex,
                        umiToolsUmiPatternRegex=input_umiToolsUmiPatternRegex,
                        surrogateHammingThresholdStrict=input_surrogateHammingThresholdStrict,
                        barcodeHammingThresholdStrict=input_barcodeHammingThresholdStrict,
                        protospacerHammingThresholdStrict=input_protospacerHammingThresholdStrict,
                        dockerImage=dockerImage,
                        preemptible=preemptible,
                        diskGB=diskGB,
                        memoryGB=memoryGB,
                        maxRetries=maxRetries,
                        diskType=diskType,
                        cpus=cpus
                }


                Map[String, Float] editing_efficiency_dict = {"protospacer_editing_efficiency":GuideCount_ScreenId.protospacer_editing_efficiency,
                "surrogate_editing_efficiency": GuideCount_ScreenId.surrogate_editing_efficiency,
                "barcode_editing_efficiency": GuideCount_ScreenId.barcode_editing_efficiency}

                Map[String, File] supplementary_files_dict = {"match_set_whitelist_reporter_observed_sequence_counter_series_results": GuideCount_ScreenId.match_set_whitelist_reporter_observed_sequence_counter_series_results,
                "mutations_results": GuideCount_ScreenId.mutations_results,
                "linked_mutation_counters": GuideCount_ScreenId.linked_mutation_counters,
                "protospacer_total_mutation_histogram_pdf": GuideCount_ScreenId.protospacer_total_mutation_histogram_pdf,
                "surrogate_total_mutation_histogram_pdf": GuideCount_ScreenId.surrogate_total_mutation_histogram_pdf,
                "barcode_total_mutation_histogram_pdf": GuideCount_ScreenId.barcode_total_mutation_histogram_pdf,
                "surrogate_trinucleotide_mutational_signature": GuideCount_ScreenId.surrogate_trinucleotide_mutational_signature,
                "surrogate_trinucleotide_positional_signature": GuideCount_ScreenId.surrogate_trinucleotide_positional_signature,
                "whitelist_guide_reporter_df": GuideCount_ScreenId.whitelist_guide_reporter_df,
                "count_series_result": GuideCount_ScreenId.count_series_result
                }

                Pair[Pair[AnnotatedSample,Array[String]], File] annotated_count_result = (annotatedSamplePair, GuideCount_ScreenId.count_result)
                Pair[Pair[AnnotatedSample,Array[String]], Map[String, Float]] annotated_editing_efficiencies = (annotatedSamplePair, editing_efficiency_dict)
                Pair[Pair[AnnotatedSample,Array[String]], Map[String, File]] annotated_supplementary_files = (annotatedSamplePair, supplementary_files_dict)

            }
            Array[Pair[Pair[AnnotatedSample,Array[String]], File]] annotated_count_result_list = annotated_count_result
            Pair[String, Array[Pair[Pair[AnnotatedSample,Array[String]], File]]] screen_countResults_pair = (screenId, annotated_count_result_list)

            Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, Float]]] annotated_editing_efficiencies_list = annotated_editing_efficiencies
            Pair[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, Float]]]] screen_editingEfficiencies_pair = (screenId, annotated_editing_efficiencies_list)

            Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, File]]] annotated_supplementary_files_list = annotated_supplementary_files
            Pair[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, File]]]] screen_supplementaryFiles_pair = (screenId, annotated_supplementary_files_list)
        }

        

        # TODO: Perform ADATA/BDATA for each screen here! Will use the sampleInfoVars for the sample , Array[Array[String]] sampleInfoVarsScreenList = sampleInfoVars
    }

    Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], File]]] screen_countResults_map = as_map(select_all(screen_countResults_pair))
    Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, Float]]]] screen_editingEfficiencies_map = as_map(select_all(screen_editingEfficiencies_pair))
    Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, File]]]] screen_supplementaryFiles_map = as_map(select_all(screen_supplementaryFiles_pair))

    output {
        Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], File]]] output_screen_countResults_map = screen_countResults_map
        Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, Float]]]] output_screen_editingEfficiencies_map = screen_editingEfficiencies_map
        Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, File]]]] output_screen_supplementaryFiles_map = screen_supplementaryFiles_map
    }

}