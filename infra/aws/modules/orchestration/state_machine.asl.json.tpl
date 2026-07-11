{
  "Comment": "Video generation pipeline: video_gen + tts + bg_audio in parallel, then lip_sync, then Fargate ffmpeg assembly (final state - the assembly container marks the job COMPLETE itself, see workers/assembly/main.py)",
  "StartAt": "ParallelGeneration",
  "States": {
    "ParallelGeneration": {
      "Type": "Parallel",
      "ResultPath": "$.parallel_result",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "UpdateJobFailed"
        }
      ],
      "Branches": [
        {
          "StartAt": "InvokeVideoGen",
          "States": {
            "InvokeVideoGen": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
              "Parameters": {
                "FunctionName": "${invoke_video_gen_arn}",
                "Payload": {
                  "job_id.$": "$.job_id",
                  "prompt.$": "$.prompt",
                  "params.$": "$.params",
                  "task_token.$": "$$.Task.Token"
                }
              },
              "TimeoutSeconds": 300,
              "End": true
            }
          }
        },
        {
          "StartAt": "InvokeTTS",
          "States": {
            "InvokeTTS": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
              "Parameters": {
                "FunctionName": "${invoke_tts_arn}",
                "Payload": {
                  "job_id.$": "$.job_id",
                  "prompt.$": "$.prompt",
                  "params.$": "$.params",
                  "task_token.$": "$$.Task.Token"
                }
              },
              "TimeoutSeconds": 180,
              "End": true
            }
          }
        },
        {
          "StartAt": "InvokeBGAudio",
          "States": {
            "InvokeBGAudio": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
              "Parameters": {
                "FunctionName": "${invoke_bg_audio_arn}",
                "Payload": {
                  "job_id.$": "$.job_id",
                  "prompt.$": "$.prompt",
                  "params.$": "$.params",
                  "task_token.$": "$$.Task.Token"
                }
              },
              "TimeoutSeconds": 300,
              "End": true
            }
          }
        }
      ],
      "Next": "InvokeLipSync"
    },
    "InvokeLipSync": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke.waitForTaskToken",
      "Parameters": {
        "FunctionName": "${invoke_lip_sync_arn}",
        "Payload": {
          "job_id.$": "$.job_id",
          "video_output_key.$": "$.parallel_result[0].output_key",
          "audio_output_key.$": "$.parallel_result[1].output_key",
          "task_token.$": "$$.Task.Token"
        }
      },
      "TimeoutSeconds": 280,
      "ResultPath": "$.lip_sync_result",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "UpdateJobFailed"
        }
      ],
      "Next": "PrepareAssembly"
    },
    "PrepareAssembly": {
      "Type": "Pass",
      "Parameters": {
        "output_key.$": "States.Format('{}/assembly/final.mp4', $.job_id)"
      },
      "ResultPath": "$.assembly",
      "Next": "AssembleFinalVideo"
    },
    "AssembleFinalVideo": {
      "Type": "Task",
      "Resource": "arn:aws:states:::ecs:runTask.sync",
      "Parameters": {
        "LaunchType": "FARGATE",
        "Cluster": "${ecs_cluster_arn}",
        "TaskDefinition": "${assembly_task_definition_arn}",
        "NetworkConfiguration": {
          "AwsvpcConfiguration": {
            "Subnets": ${assembly_subnet_ids_json},
            "SecurityGroups": ["${assembly_security_group_id}"],
            "AssignPublicIp": "ENABLED"
          }
        },
        "Overrides": {
          "ContainerOverrides": [
            {
              "Name": "assembly",
              "Environment": [
                { "Name": "JOB_ID", "Value.$": "$.job_id" },
                { "Name": "LIP_SYNC_KEY", "Value.$": "$.lip_sync_result.output_key" },
                { "Name": "BG_AUDIO_KEY", "Value.$": "$.parallel_result[2].output_key" },
                { "Name": "OUTPUT_KEY", "Value.$": "$.assembly.output_key" }
              ]
            }
          ]
        }
      },
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "ResultPath": "$.error",
          "Next": "UpdateJobFailed"
        }
      ],
      "End": true
    },
    "UpdateJobFailed": {
      "Type": "Task",
      "Resource": "${update_job_failed_arn}",
      "End": true
    }
  }
}
