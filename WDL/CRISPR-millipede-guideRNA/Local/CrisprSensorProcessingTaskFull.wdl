version development

import "BBMapDemultiplex.wdl" as demultiplex
import "CrisprSelfEditMapping.wdl" as mapping

task UmiToolsExtractTask {
    input {
        File inputRead1
        File? inputRead2
        String r1U6BarcodeExtractionRegex
        String? r24ntBarcodeExtractionRegex
        String sampleName
    }

	String logFileFn="${sampleName}.umitools_log.txt"
	String outputRead1Fn="${sampleName}.umitools.R1.fastq"
	String outputRead2Fn="${sampleName}.umitools.R2.fastq"
	String outputFilteredRead1Fn="${sampleName}.umitools.filtered.R1.fastq"
	String outputFilteredRead2Fn="${sampleName}.umitools.filtered.R2.fastq"
	
    Boolean inputRead2Defined = defined(inputRead2)
    Boolean r24ntBarcodeExtractionRegexDefined = defined(r24ntBarcodeExtractionRegex)

	command <<<
        if [ ~{inputRead2Defined} ] && [ ~{r24ntBarcodeExtractionRegexDefined} ]; then
            echo "Running R1+R2 Mode"
            umi_tools extract --extract-method=regex \
            --stdin ~{inputRead1} \
            --read2-in ~{inputRead2} \
            --bc-pattern ~{r1U6BarcodeExtractionRegex} \
            --bc-pattern2 ~{r24ntBarcodeExtractionRegex} \
            -L ~{logFileFn} \
            --stdout ~{outputRead1Fn} \
            --read2-out ~{outputRead2Fn} \
            --filtered-out ~{outputFilteredRead1Fn} \
            --filtered-out2 ~{outputFilteredRead2Fn}
            echo "Completed"
        else
            echo "Running R1-only Mode"
            umi_tools extract --extract-method=regex \
            --stdin ~{inputRead1} \
            --bc-pattern=~{r1U6BarcodeExtractionRegex} \
            -L ~{logFileFn} \
            --stdout ~{outputRead1Fn} \
            --filtered-out ~{outputFilteredRead1Fn}
            echo "Completed"
        fi

        awk '{print $1/4}' <(wc -l < ~{outputRead1Fn}) > output_read_count.txt
        awk '{print $1/4}' <(wc -l < ~{outputFilteredRead1Fn}) > output_filtered_read_count.txt

        echo "Output read count:"
        cat output_read_count.txt
        echo "Output filtered read count:"
        cat output_filtered_read_count.txt
    >>>

    output {
		File outputRead1="${outputRead1Fn}"
		File? outputRead2="${outputRead2Fn}"
		File outputFilteredRead1="${outputFilteredRead1Fn}"
		File? outputFilteredRead2="${outputFilteredRead2Fn}"
		File logFile="${logFileFn}"
		Float outputRead1ReadCount=read_float('output_read_count.txt')
		Float outputFilteredRead1ReadCount=read_float('output_filtered_read_count.txt')
	}

	runtime {
		docker: "quay.io/biocontainers/umi_tools:1.1.4--py38he5da3d1_2"
	}
}

workflow CrisprSensorPreprocessing_Workflow {
    input {
        # FOR UMI TOOLS
        File? rawFastqR1 # IF 
        File? rawFastqR2
        String? r1U6BarcodeExtractionRegex # TODO: Rename to distinguish between the other REGEX
        String? r24ntBarcodeExtractionRegex # TODO: Rename to distinguish between the other REGEX
        String sampleName

        # TO SKIP UMI TOOLS STEP
        File? umiToolsFastqR1
		File? umiToolsFastqR2

        #
        #   FOR DEMULTIPLEX
        #
        File? i5IndexStringTextFile
        Array[String]? i5IndexList
        File? barcodeIndexStringTextFile
        Array[String]? barcodeIndexList
        
        Int i5Hamming 
        Int barcodeHamming

        #
        #   FOR COUNTING
        #
        #NEW contains the demultiplex to screen ID map
        String? input_screenId
        Map[String, String]? input_i5ToScreenidMap
        Map[String, String]? input_barcodeToScreenidMap
        Map[String, Map[String, String]]? input_i5ToBarcodeToScreenidMap

        #NEW contains the demultiplex to sample Information
        Array[String]? input_sampleInfoVarnames
        Array[String]? input_sampleInfoVars
        Map[String, Array[String]]? input_i5ToSampleInfoVarsMap
        Map[String, Array[String]]? input_barcodeToSampleInfoVarsMap
        Map[String, Map[String, Array[String]]]? input_i5ToBarcodeToSampleInfoVarsMap

        # NEW contains the screenId to reporter TSV map
        File? input_whitelistGuideReporterTsv
        Map[String, File]? input_screenIdToWhitelistGuideReporterTsv
        Map[String, File]? input_screenIdToGuideAnnotationsTsv # NOTE: This can be based on the IGVF guide specification or any flexible schema

        # NEW contains annotations of demultiplex to annotations table
        String? input_umiToolsHeaderBarcodeRegex
        String? input_umiToolsUmiPatternRegex
        
        Int? input_surrogateHammingThresholdStrict
        Int? input_barcodeHammingThresholdStrict
        Int? input_protospacerHammingThresholdStrict
    }

    # Extract relevant sequences using UMI tools
    # TODO: Once we have the seqspec tool, perhaps that plus the extract task can be moddularized into a new workflow.
    if(!defined(umiToolsFastqR1)){
        call UmiToolsExtractTask {
            input:
                inputRead1=select_first([rawFastqR1]),
                inputRead2=rawFastqR2,
                r1U6BarcodeExtractionRegex=select_first([r1U6BarcodeExtractionRegex]),
                r24ntBarcodeExtractionRegex=r24ntBarcodeExtractionRegex,
                sampleName=sampleName
        }
    
        # Demultiplex the UMI tools result
        call demultiplex.BBMapDemultiplexOrchestratorWorkflow as demultiplexWorkflowUmiToolsPerformed {
            input:
                inputRead1=UmiToolsExtractTask.outputRead1,
                inputRead2=UmiToolsExtractTask.outputRead2,
                i5IndexStringTextFile=i5IndexStringTextFile,
                i5IndexList=i5IndexList,
                barcodeIndexStringTextFile=barcodeIndexStringTextFile,
                barcodeIndexList=barcodeIndexList,
                i5Hamming=i5Hamming,
                barcodeHamming=barcodeHamming,
                sampleName=sampleName,

                # Mapping from indices to screen name
                screenId=input_screenId,
                i5ToScreenidMap=input_i5ToScreenidMap,
                barcodeToScreenidMap=input_barcodeToScreenidMap,
                i5ToBarcodeToScreenidMap=input_i5ToBarcodeToScreenidMap,

                # Mapping from indices to sample annotations
                sampleInfoVars=input_sampleInfoVars,
                i5ToSampleInfoVarsMap=input_i5ToSampleInfoVarsMap,
                barcodeToSampleInfoVarsMap=input_barcodeToSampleInfoVarsMap,
                i5ToBarcodeToSampleInfoVarsMap=input_i5ToBarcodeToSampleInfoVarsMap
        }
    } 
    if(defined(umiToolsFastqR1)){
        call demultiplex.BBMapDemultiplexOrchestratorWorkflow as demultiplexWorkflowUmiToolsSkipped {
            input:
                inputRead1=select_first([umiToolsFastqR1]),
                inputRead2=umiToolsFastqR2,
                i5IndexStringTextFile=i5IndexStringTextFile,
                i5IndexList=i5IndexList,
                barcodeIndexStringTextFile=barcodeIndexStringTextFile,
                barcodeIndexList=barcodeIndexList,
                i5Hamming=i5Hamming,
                barcodeHamming=barcodeHamming,
                sampleName=sampleName,

                # Mapping from indices to screen name
                screenId=input_screenId,
                i5ToScreenidMap=input_i5ToScreenidMap,
                barcodeToScreenidMap=input_barcodeToScreenidMap,
                i5ToBarcodeToScreenidMap=input_i5ToBarcodeToScreenidMap,

                # Mapping from indices to sample annotations
                sampleInfoVars=input_sampleInfoVars,
                i5ToSampleInfoVarsMap=input_i5ToSampleInfoVarsMap,
                barcodeToSampleInfoVarsMap=input_barcodeToSampleInfoVarsMap,
                i5ToBarcodeToSampleInfoVarsMap=input_i5ToBarcodeToSampleInfoVarsMap
        }
    }

    Map[String, Array[Pair[AnnotatedSample, Array[String]]]] output_screenIdToSampleMap_final = select_first([demultiplexWorkflowUmiToolsSkipped.output_screenIdToSampleMap, demultiplexWorkflowUmiToolsPerformed.output_screenIdToSampleMap])

    call mapping.CrisprSelfEditMappingOrchestratorWorkflow as mappingWorkflow {
        input:
            input_screenIdToSampleMap=output_screenIdToSampleMap_final,

            input_whitelistGuideReporterTsv=input_whitelistGuideReporterTsv,
            input_screenIdToWhitelistGuideReporterTsv=input_screenIdToWhitelistGuideReporterTsv,
            input_screenIdToGuideAnnotationsTsv=input_screenIdToGuideAnnotationsTsv,

            input_umiToolsHeaderBarcodeRegex=input_umiToolsHeaderBarcodeRegex,
            input_umiToolsUmiPatternRegex=input_umiToolsUmiPatternRegex,
        
            input_surrogateHammingThresholdStrict=input_surrogateHammingThresholdStrict,
            input_barcodeHammingThresholdStrict=input_barcodeHammingThresholdStrict,
            input_protospacerHammingThresholdStrict=input_protospacerHammingThresholdStrict
    }

    
	# TODO: Since we have a MAP, perhaps someone can input a TSV of the sample sheet, then we can return a final table with the samples attached. Or we can return a table without the sample sheet. Make this into another workflow for preprocessing all outputs

    output {
        #
        #   UMI Tools Outputs
        #
        File? umiToolsExtractedOutputRead1 = UmiToolsExtractTask.outputRead1
        File? umiToolsExtractedOutputRead2 = UmiToolsExtractTask.outputRead2
        File? umiToolsExtractedOutputFilteredRead1=UmiToolsExtractTask.outputFilteredRead1
        File? umiToolsExtractedOutputFilteredRead2=UmiToolsExtractTask.outputFilteredRead2
        File? umiToolsExtractTaskLogFile=UmiToolsExtractTask.logFile
        Float? umiToolsExtractOutputRead1ReadCount = UmiToolsExtractTask.outputRead1ReadCount
        Float? umiToolsExtractOutputFilteredRead1ReadCount = UmiToolsExtractTask.outputFilteredRead1ReadCount

        #
        #   Demultiplexing Outputs
        #
        Map[String, Array[Pair[AnnotatedSample, Array[String]]]] output_screenIdToSampleMap = output_screenIdToSampleMap_final

        #
        # Guide Mapping Outputs
        #
        Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], File]]] output_screen_countResults_map = mappingWorkflow.output_screen_countResults_map
        Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, Float]]]] output_screen_editingEfficiencies_map = mappingWorkflow.output_screen_editingEfficiencies_map
        Map[String, Array[Pair[Pair[AnnotatedSample,Array[String]], Map[String, File]]]] output_screen_supplementaryFiles_map = mappingWorkflow.output_screen_supplementaryFiles_map
    }
}


