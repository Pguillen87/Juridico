export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never;
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      graphql: {
        Args: {
          extensions?: Json;
          operationName?: string;
          query?: string;
          variables?: Json;
        };
        Returns: Json;
      };
    };
    Enums: {
      [_ in never]: never;
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string;
          actor_user_id: string | null;
          audit_scope: string;
          correlation_id: string;
          created_at: string;
          entity_id: string | null;
          entity_type: string;
          id: number;
          metadata: Json;
          office_id: string;
        };
        Insert: {
          action: string;
          actor_user_id?: string | null;
          audit_scope: string;
          correlation_id?: string;
          created_at?: string;
          entity_id?: string | null;
          entity_type: string;
          id?: never;
          metadata?: Json;
          office_id: string;
        };
        Update: {
          action?: string;
          actor_user_id?: string | null;
          audit_scope?: string;
          correlation_id?: string;
          created_at?: string;
          entity_id?: string | null;
          entity_type?: string;
          id?: never;
          metadata?: Json;
          office_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'audit_log_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
        ];
      };
      client: {
        Row: {
          created_at: string;
          created_by: string;
          id: string;
          office_id: string;
          party_id: string;
          status: string;
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          created_by: string;
          id?: string;
          office_id: string;
          party_id: string;
          status?: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          created_by?: string;
          id?: string;
          office_id?: string;
          party_id?: string;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'client_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'client_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'client_office_id_party_id_fkey';
            columns: ['office_id', 'party_id'];
            isOneToOne: false;
            referencedRelation: 'party';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      client_related_party: {
        Row: {
          client_id: string;
          confirmation_status: string;
          confirmed_at: string | null;
          confirmed_by: string | null;
          created_at: string;
          created_by: string;
          id: string;
          notes: string | null;
          office_id: string;
          party_id: string;
          relation_type: string;
          status: string;
          updated_at: string;
        };
        Insert: {
          client_id: string;
          confirmation_status?: string;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          created_by: string;
          id?: string;
          notes?: string | null;
          office_id: string;
          party_id: string;
          relation_type: string;
          status?: string;
          updated_at?: string;
        };
        Update: {
          client_id?: string;
          confirmation_status?: string;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          created_by?: string;
          id?: string;
          notes?: string | null;
          office_id?: string;
          party_id?: string;
          relation_type?: string;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'client_related_party_confirmed_by_fkey';
            columns: ['confirmed_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'client_related_party_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'client_related_party_office_id_client_id_fkey';
            columns: ['office_id', 'client_id'];
            isOneToOne: false;
            referencedRelation: 'client';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'client_related_party_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'client_related_party_office_id_party_id_fkey';
            columns: ['office_id', 'party_id'];
            isOneToOne: false;
            referencedRelation: 'party';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      detected_change: {
        Row: {
          change_fingerprint: string;
          change_type: string;
          comparison_id: string;
          created_at: string;
          detected_at: string;
          id: string;
          office_id: string;
          process_id: string;
        };
        Insert: {
          change_fingerprint: string;
          change_type?: string;
          comparison_id: string;
          created_at?: string;
          detected_at?: string;
          id?: string;
          office_id: string;
          process_id: string;
        };
        Update: {
          change_fingerprint?: string;
          change_type?: string;
          comparison_id?: string;
          created_at?: string;
          detected_at?: string;
          id?: string;
          office_id?: string;
          process_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'detected_change_office_id_comparison_id_process_id_fkey';
            columns: ['office_id', 'comparison_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'process_comparison';
            referencedColumns: ['office_id', 'id', 'process_id'];
          },
        ];
      };
      legal_process: {
        Row: {
          client_id: string;
          cnj_number: string;
          created_at: string;
          created_by: string;
          id: string;
          is_public: boolean;
          monitoring_status: string;
          office_id: string;
          status: string;
          system: string | null;
          tribunal: string;
          updated_at: string;
        };
        Insert: {
          client_id: string;
          cnj_number: string;
          created_at?: string;
          created_by: string;
          id?: string;
          is_public?: boolean;
          monitoring_status?: string;
          office_id: string;
          status?: string;
          system?: string | null;
          tribunal: string;
          updated_at?: string;
        };
        Update: {
          client_id?: string;
          cnj_number?: string;
          created_at?: string;
          created_by?: string;
          id?: string;
          is_public?: boolean;
          monitoring_status?: string;
          office_id?: string;
          status?: string;
          system?: string | null;
          tribunal?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'legal_process_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'legal_process_office_id_client_id_fkey';
            columns: ['office_id', 'client_id'];
            isOneToOne: false;
            referencedRelation: 'client';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'legal_process_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
        ];
      };
      monitoring_configuration: {
        Row: {
          active: boolean;
          created_at: string;
          created_by: string | null;
          id: string;
          office_id: string;
          timezone: string;
          updated_at: string;
          version: number;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          office_id: string;
          timezone: string;
          updated_at?: string;
          version?: number;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          created_by?: string | null;
          id?: string;
          office_id?: string;
          timezone?: string;
          updated_at?: string;
          version?: number;
        };
        Relationships: [
          {
            foreignKeyName: 'monitoring_configuration_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'monitoring_configuration_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
        ];
      };
      monitoring_schedule: {
        Row: {
          active: boolean;
          created_at: string;
          days_of_week: number[];
          id: string;
          local_time: string;
          monitoring_configuration_id: string;
          office_id: string;
          timezone: string;
          updated_at: string;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          days_of_week: number[];
          id?: string;
          local_time: string;
          monitoring_configuration_id: string;
          office_id: string;
          timezone: string;
          updated_at?: string;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          days_of_week?: number[];
          id?: string;
          local_time?: string;
          monitoring_configuration_id?: string;
          office_id?: string;
          timezone?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'monitoring_schedule_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'monitoring_schedule_office_id_monitoring_configuration_id_fkey';
            columns: ['office_id', 'monitoring_configuration_id'];
            isOneToOne: false;
            referencedRelation: 'monitoring_configuration';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      office: {
        Row: {
          created_at: string;
          id: string;
          is_active: boolean;
          name: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          name: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
        };
        Relationships: [];
      };
      party: {
        Row: {
          created_at: string;
          created_by: string;
          display_name: string;
          id: string;
          normalized_name: string;
          office_id: string;
          party_type: string;
          status: string;
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          created_by: string;
          display_name: string;
          id?: string;
          normalized_name: string;
          office_id: string;
          party_type: string;
          status?: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          created_by?: string;
          display_name?: string;
          id?: string;
          normalized_name?: string;
          office_id?: string;
          party_type?: string;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'party_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'party_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
        ];
      };
      process_comparison: {
        Row: {
          changed_fields: Json;
          comparison_hash: string;
          comparison_version: string;
          created_at: string;
          current_snapshot_id: string;
          id: string;
          normalized_diff: Json;
          office_id: string;
          previous_snapshot_id: string | null;
          process_id: string;
          reason_code: string | null;
          result: string;
        };
        Insert: {
          changed_fields?: Json;
          comparison_hash: string;
          comparison_version: string;
          created_at?: string;
          current_snapshot_id: string;
          id?: string;
          normalized_diff?: Json;
          office_id: string;
          previous_snapshot_id?: string | null;
          process_id: string;
          reason_code?: string | null;
          result: string;
        };
        Update: {
          changed_fields?: Json;
          comparison_hash?: string;
          comparison_version?: string;
          created_at?: string;
          current_snapshot_id?: string;
          id?: string;
          normalized_diff?: Json;
          office_id?: string;
          previous_snapshot_id?: string | null;
          process_id?: string;
          reason_code?: string | null;
          result?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'process_comparison_office_id_current_snapshot_id_fkey';
            columns: ['office_id', 'current_snapshot_id'];
            isOneToOne: false;
            referencedRelation: 'process_snapshot';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'process_comparison_office_id_previous_snapshot_id_fkey';
            columns: ['office_id', 'previous_snapshot_id'];
            isOneToOne: false;
            referencedRelation: 'process_snapshot';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'process_comparison_office_id_process_id_fkey';
            columns: ['office_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'legal_process';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      process_import_preview: {
        Row: {
          consumed_at: string | null;
          consumed_summary: Json | null;
          content_hash: string;
          created_at: string;
          created_by: string;
          expires_at: string;
          id: string;
          normalized_rows: Json;
          office_id: string;
          parser_version: string;
          status: string;
          summary: Json;
        };
        Insert: {
          consumed_at?: string | null;
          consumed_summary?: Json | null;
          content_hash: string;
          created_at?: string;
          created_by: string;
          expires_at?: string;
          id?: string;
          normalized_rows: Json;
          office_id: string;
          parser_version: string;
          status?: string;
          summary?: Json;
        };
        Update: {
          consumed_at?: string | null;
          consumed_summary?: Json | null;
          content_hash?: string;
          created_at?: string;
          created_by?: string;
          expires_at?: string;
          id?: string;
          normalized_rows?: Json;
          office_id?: string;
          parser_version?: string;
          status?: string;
          summary?: Json;
        };
        Relationships: [
          {
            foreignKeyName: 'process_import_preview_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'process_import_preview_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
        ];
      };
      process_party: {
        Row: {
          confirmation_status: string;
          confirmed_at: string | null;
          confirmed_by: string | null;
          created_at: string;
          created_by: string;
          id: string;
          notes: string | null;
          office_id: string;
          party_id: string;
          process_id: string;
          role_in_process: string;
          source: string;
          status: string;
          updated_at: string;
        };
        Insert: {
          confirmation_status?: string;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          created_by: string;
          id?: string;
          notes?: string | null;
          office_id: string;
          party_id: string;
          process_id: string;
          role_in_process: string;
          source: string;
          status?: string;
          updated_at?: string;
        };
        Update: {
          confirmation_status?: string;
          confirmed_at?: string | null;
          confirmed_by?: string | null;
          created_at?: string;
          created_by?: string;
          id?: string;
          notes?: string | null;
          office_id?: string;
          party_id?: string;
          process_id?: string;
          role_in_process?: string;
          source?: string;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'process_party_confirmed_by_fkey';
            columns: ['confirmed_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'process_party_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'process_party_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'process_party_office_id_party_id_fkey';
            columns: ['office_id', 'party_id'];
            isOneToOne: false;
            referencedRelation: 'party';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'process_party_office_id_process_id_fkey';
            columns: ['office_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'legal_process';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      process_snapshot: {
        Row: {
          created_at: string;
          evidence_ref: string | null;
          id: string;
          missing_fields: Json;
          normalized_data: Json;
          normalizer_version: string;
          office_id: string;
          process_id: string;
          provider_id: string;
          query_execution_id: string;
          snapshot_hash: string;
          source: string;
        };
        Insert: {
          created_at?: string;
          evidence_ref?: string | null;
          id?: string;
          missing_fields?: Json;
          normalized_data: Json;
          normalizer_version: string;
          office_id: string;
          process_id: string;
          provider_id: string;
          query_execution_id: string;
          snapshot_hash: string;
          source: string;
        };
        Update: {
          created_at?: string;
          evidence_ref?: string | null;
          id?: string;
          missing_fields?: Json;
          normalized_data?: Json;
          normalizer_version?: string;
          office_id?: string;
          process_id?: string;
          provider_id?: string;
          query_execution_id?: string;
          snapshot_hash?: string;
          source?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'process_snapshot_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'process_snapshot_office_id_process_id_fkey';
            columns: ['office_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'legal_process';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'process_snapshot_office_id_query_execution_id_fkey';
            columns: ['office_id', 'query_execution_id'];
            isOneToOne: true;
            referencedRelation: 'query_execution';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      provider_exchange: {
        Row: {
          contract_version: number;
          correlation_id: string;
          created_at: string;
          error_code: string | null;
          id: string;
          normalized_result: Json | null;
          office_id: string;
          process_id: string;
          provider_id: string;
          request_fingerprint: string;
          result_kind: string;
          result_status: string;
          source: string;
          subject_ref: string;
        };
        Insert: {
          contract_version: number;
          correlation_id: string;
          created_at?: string;
          error_code?: string | null;
          id?: string;
          normalized_result?: Json | null;
          office_id: string;
          process_id: string;
          provider_id: string;
          request_fingerprint: string;
          result_kind: string;
          result_status: string;
          source: string;
          subject_ref: string;
        };
        Update: {
          contract_version?: number;
          correlation_id?: string;
          created_at?: string;
          error_code?: string | null;
          id?: string;
          normalized_result?: Json | null;
          office_id?: string;
          process_id?: string;
          provider_id?: string;
          request_fingerprint?: string;
          result_kind?: string;
          result_status?: string;
          source?: string;
          subject_ref?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'provider_exchange_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'provider_exchange_office_id_process_id_fkey';
            columns: ['office_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'legal_process';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      query_execution: {
        Row: {
          attempt_number: number;
          capability: string;
          correlation_id: string;
          created_at: string;
          duration_ms: number | null;
          error_code: string | null;
          error_message_sanitized: string | null;
          finished_at: string | null;
          http_status: number | null;
          id: string;
          office_id: string;
          process_id: string;
          provider_exchange_id: string | null;
          provider_id: string;
          query_job_id: string;
          started_at: string;
          status: string;
        };
        Insert: {
          attempt_number: number;
          capability: string;
          correlation_id: string;
          created_at?: string;
          duration_ms?: number | null;
          error_code?: string | null;
          error_message_sanitized?: string | null;
          finished_at?: string | null;
          http_status?: number | null;
          id?: string;
          office_id: string;
          process_id: string;
          provider_exchange_id?: string | null;
          provider_id: string;
          query_job_id: string;
          started_at?: string;
          status?: string;
        };
        Update: {
          attempt_number?: number;
          capability?: string;
          correlation_id?: string;
          created_at?: string;
          duration_ms?: number | null;
          error_code?: string | null;
          error_message_sanitized?: string | null;
          finished_at?: string | null;
          http_status?: number | null;
          id?: string;
          office_id?: string;
          process_id?: string;
          provider_exchange_id?: string | null;
          provider_id?: string;
          query_job_id?: string;
          started_at?: string;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'query_execution_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'query_execution_office_id_process_id_fkey';
            columns: ['office_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'legal_process';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'query_execution_office_id_provider_exchange_id_fkey';
            columns: ['office_id', 'provider_exchange_id'];
            isOneToOne: false;
            referencedRelation: 'provider_exchange';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'query_execution_office_id_query_job_id_fkey';
            columns: ['office_id', 'query_job_id'];
            isOneToOne: false;
            referencedRelation: 'query_job';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      query_job: {
        Row: {
          attempt_count: number;
          available_at: string;
          capability: string;
          correlation_id: string;
          created_at: string;
          created_by: string | null;
          finished_at: string | null;
          id: string;
          idempotency_key: string;
          job_kind: string;
          last_error_code: string | null;
          last_error_message: string | null;
          lease_expires_at: string | null;
          lease_token: string | null;
          locked_by: string | null;
          max_attempts: number;
          office_id: string;
          process_id: string;
          provider_id: string;
          request_fingerprint: string;
          scheduled_window_utc: string | null;
          status: string;
          updated_at: string;
        };
        Insert: {
          attempt_count?: number;
          available_at?: string;
          capability: string;
          correlation_id: string;
          created_at?: string;
          created_by?: string | null;
          finished_at?: string | null;
          id?: string;
          idempotency_key: string;
          job_kind: string;
          last_error_code?: string | null;
          last_error_message?: string | null;
          lease_expires_at?: string | null;
          lease_token?: string | null;
          locked_by?: string | null;
          max_attempts?: number;
          office_id: string;
          process_id: string;
          provider_id: string;
          request_fingerprint: string;
          scheduled_window_utc?: string | null;
          status?: string;
          updated_at?: string;
        };
        Update: {
          attempt_count?: number;
          available_at?: string;
          capability?: string;
          correlation_id?: string;
          created_at?: string;
          created_by?: string | null;
          finished_at?: string | null;
          id?: string;
          idempotency_key?: string;
          job_kind?: string;
          last_error_code?: string | null;
          last_error_message?: string | null;
          lease_expires_at?: string | null;
          lease_token?: string | null;
          locked_by?: string | null;
          max_attempts?: number;
          office_id?: string;
          process_id?: string;
          provider_id?: string;
          request_fingerprint?: string;
          scheduled_window_utc?: string | null;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'query_job_created_by_fkey';
            columns: ['created_by'];
            isOneToOne: false;
            referencedRelation: 'user_profile';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'query_job_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'query_job_office_id_process_id_fkey';
            columns: ['office_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'legal_process';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      rate_limit_bucket: {
        Row: {
          actor_user_id: string;
          office_id: string;
          operation: string;
          request_count: number;
          updated_at: string;
          window_started_at: string;
        };
        Insert: {
          actor_user_id: string;
          office_id: string;
          operation: string;
          request_count: number;
          updated_at?: string;
          window_started_at: string;
        };
        Update: {
          actor_user_id?: string;
          office_id?: string;
          operation?: string;
          request_count?: number;
          updated_at?: string;
          window_started_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'rate_limit_bucket_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
        ];
      };
      raw_provider_payload: {
        Row: {
          correlation_id: string;
          created_at: string;
          id: string;
          office_id: string;
          payload: Json;
          payload_bytes: number;
          payload_hash: string;
          process_id: string;
          provider_exchange_id: string;
          provider_id: string;
          received_at: string;
          sanitization_version: string;
          source: string;
        };
        Insert: {
          correlation_id: string;
          created_at?: string;
          id?: string;
          office_id: string;
          payload: Json;
          payload_bytes: number;
          payload_hash: string;
          process_id: string;
          provider_exchange_id: string;
          provider_id: string;
          received_at: string;
          sanitization_version: string;
          source: string;
        };
        Update: {
          correlation_id?: string;
          created_at?: string;
          id?: string;
          office_id?: string;
          payload?: Json;
          payload_bytes?: number;
          payload_hash?: string;
          process_id?: string;
          provider_exchange_id?: string;
          provider_id?: string;
          received_at?: string;
          sanitization_version?: string;
          source?: string;
        };
        Relationships: [
          {
            foreignKeyName: 'raw_provider_payload_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
          {
            foreignKeyName: 'raw_provider_payload_office_id_process_id_fkey';
            columns: ['office_id', 'process_id'];
            isOneToOne: false;
            referencedRelation: 'legal_process';
            referencedColumns: ['office_id', 'id'];
          },
          {
            foreignKeyName: 'raw_provider_payload_office_id_provider_exchange_id_fkey';
            columns: ['office_id', 'provider_exchange_id'];
            isOneToOne: false;
            referencedRelation: 'provider_exchange';
            referencedColumns: ['office_id', 'id'];
          },
        ];
      };
      user_profile: {
        Row: {
          created_at: string;
          id: string;
          is_active: boolean;
          is_owner: boolean;
          name: string;
          office_id: string;
          role: Database['public']['Enums']['user_role'];
        };
        Insert: {
          created_at?: string;
          id: string;
          is_active?: boolean;
          is_owner?: boolean;
          name: string;
          office_id: string;
          role: Database['public']['Enums']['user_role'];
        };
        Update: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          is_owner?: boolean;
          name?: string;
          office_id?: string;
          role?: Database['public']['Enums']['user_role'];
        };
        Relationships: [
          {
            foreignKeyName: 'user_profile_office_id_fkey';
            columns: ['office_id'];
            isOneToOne: false;
            referencedRelation: 'office';
            referencedColumns: ['id'];
          },
        ];
      };
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      can_view_operational_row: {
        Args: { p_office_id: string };
        Returns: boolean;
      };
      change_user_role: {
        Args: {
          p_new_role: Database['public']['Enums']['user_role'];
          p_target_user_id: string;
        };
        Returns: {
          created_at: string;
          id: string;
          is_active: boolean;
          is_owner: boolean;
          name: string;
          office_id: string;
          role: Database['public']['Enums']['user_role'];
        };
        SetofOptions: {
          from: '*';
          to: 'user_profile';
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      confirm_client_related_party: {
        Args: { p_relation_id: string };
        Returns: undefined;
      };
      confirm_process_import: { Args: { p_preview_id: string }; Returns: Json };
      confirm_process_party: {
        Args: { p_relation_id: string };
        Returns: undefined;
      };
      consume_admin_rate_limit: {
        Args: { p_operation: string };
        Returns: {
          allowed: boolean;
          current_count: number;
          limit_count: number;
          retry_after_seconds: number;
          window_seconds: number;
        }[];
      };
      create_client_related_party: {
        Args: {
          p_client_id: string;
          p_notes?: string;
          p_party_id: string;
          p_relation_type: string;
        };
        Returns: string;
      };
      create_client_with_party: {
        Args: { p_display_name: string; p_party_type: string };
        Returns: string;
      };
      create_legal_process: {
        Args: {
          p_client_id: string;
          p_cnj_number: string;
          p_is_public?: boolean;
          p_system?: string;
          p_tribunal: string;
        };
        Returns: string;
      };
      create_party: {
        Args: { p_display_name: string; p_party_type: string };
        Returns: string;
      };
      create_process_party: {
        Args: {
          p_notes?: string;
          p_party_id: string;
          p_process_id: string;
          p_role_in_process: string;
          p_source?: string;
        };
        Returns: string;
      };
      deactivate_client: { Args: { p_id: string }; Returns: undefined };
      deactivate_client_related_party: {
        Args: { p_id: string };
        Returns: undefined;
      };
      deactivate_legal_process: { Args: { p_id: string }; Returns: undefined };
      deactivate_party: { Args: { p_id: string }; Returns: undefined };
      deactivate_process_party: {
        Args: { p_relation_id: string };
        Returns: undefined;
      };
      export_administrative_audit: {
        Args: { p_action?: string; p_entity_type?: string; p_limit?: number };
        Returns: {
          action: string;
          actor_user_id: string | null;
          audit_scope: string;
          correlation_id: string;
          created_at: string;
          entity_id: string | null;
          entity_type: string;
          id: number;
          metadata: Json;
          office_id: string;
        }[];
        SetofOptions: {
          from: '*';
          to: 'audit_log';
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      get_administrative_audit: {
        Args: { p_action?: string; p_entity_type?: string; p_limit?: number };
        Returns: {
          action: string;
          actor_user_id: string | null;
          audit_scope: string;
          correlation_id: string;
          created_at: string;
          entity_id: string | null;
          entity_type: string;
          id: number;
          metadata: Json;
          office_id: string;
        }[];
        SetofOptions: {
          from: '*';
          to: 'audit_log';
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      get_auth_user_profile: {
        Args: never;
        Returns: {
          created_at: string;
          id: string;
          is_active: boolean;
          is_owner: boolean;
          name: string;
          office_id: string;
          role: Database['public']['Enums']['user_role'];
        }[];
        SetofOptions: {
          from: '*';
          to: 'user_profile';
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      get_process_import_preview: {
        Args: { p_preview_id: string };
        Returns: {
          consumed_at: string;
          consumed_summary: Json;
          content_hash: string;
          expires_at: string;
          normalized_rows: Json;
          parser_version: string;
          preview_id: string;
          status: string;
          summary: Json;
        }[];
      };
      get_provider_raw_payload: {
        Args: { p_exchange_id: string };
        Returns: {
          correlation_id: string;
          created_at: string;
          id: string;
          office_id: string;
          payload: Json;
          payload_bytes: number;
          payload_hash: string;
          process_id: string;
          provider_exchange_id: string;
          provider_id: string;
          received_at: string;
          sanitization_version: string;
          source: string;
        }[];
      };
      get_provider_raw_payload_internal: {
        Args: { p_actor_user_id: string; p_exchange_id: string };
        Returns: {
          correlation_id: string;
          created_at: string;
          id: string;
          office_id: string;
          payload: Json;
          payload_bytes: number;
          payload_hash: string;
          process_id: string;
          provider_exchange_id: string;
          provider_id: string;
          received_at: string;
          sanitization_version: string;
          source: string;
        }[];
      };
      normalize_cnj: { Args: { p_cnj: string }; Returns: string };
      phase10_compare_process_snapshot: {
        Args: {
          p_changed_fields: Json;
          p_comparison_version: string;
          p_current_snapshot_id: string;
          p_normalized_diff: Json;
          p_reason_code: string;
          p_result: string;
        };
        Returns: {
          comparison_hash: string;
          comparison_id: string;
          detected_change_id: string;
          reason_code: string;
          replayed: boolean;
          result: string;
        }[];
      };
      phase10_compare_process_snapshot_v2: {
        Args: {
          p_changed_fields: Json;
          p_comparison_version: string;
          p_current_snapshot_id: string;
          p_normalized_diff: Json;
          p_reason_code: string;
          p_result: string;
        };
        Returns: {
          changed_fields: Json;
          comparison_hash: string;
          comparison_id: string;
          detected_change_id: string;
          normalized_diff: Json;
          reason_code: string;
          replayed: boolean;
          result: string;
        }[];
      };
      phase10_get_snapshot_pair_compatible_internal: {
        Args: { p_current_snapshot_id: string };
        Returns: {
          created_at: string;
          id: string;
          missing_fields: Json;
          normalized_data: Json;
          normalizer_version: string;
          office_id: string;
          process_id: string;
          provider_id: string;
          snapshot_hash: string;
          snapshot_role: string;
          source: string;
        }[];
      };
      phase10_get_snapshot_pair_internal: {
        Args: { p_current_snapshot_id: string };
        Returns: {
          created_at: string;
          id: string;
          missing_fields: Json;
          normalized_data: Json;
          normalizer_version: string;
          office_id: string;
          process_id: string;
          provider_id: string;
          snapshot_hash: string;
          snapshot_role: string;
          source: string;
        }[];
      };
      phase10_resolve_compatible_previous_snapshot: {
        Args: { p_current_snapshot_id: string };
        Returns: string;
      };
      phase10_write_system_audit: {
        Args: {
          p_action: string;
          p_comparison_id: string;
          p_correlation_id: string;
          p_entity_id: string;
          p_entity_type: string;
          p_office_id: string;
          p_process_id: string;
          p_reason_code: string;
          p_result: string;
        };
        Returns: number;
      };
      phase6_validate_import_rows: {
        Args: { p_office_id: string; p_rows: Json };
        Returns: undefined;
      };
      phase9_claim_query_job: {
        Args: { p_lease_duration_ms?: number; p_worker_id: string };
        Returns: {
          attempt_number: number;
          capability: string;
          correlation_id: string;
          execution_id: string;
          job_id: string;
          job_kind: string;
          lease_expires_at: string;
          lease_token: string;
          office_id: string;
          process_id: string;
          provider_id: string;
          request_fingerprint: string;
          subject_ref: string;
        }[];
      };
      phase9_complete_query_execution: {
        Args: {
          p_duration_ms?: number;
          p_error_code?: string;
          p_execution_id: string;
          p_http_status?: number;
          p_job_id: string;
          p_lease_token: string;
          p_normalized_result?: Json;
          p_raw_payload?: Json;
          p_received_at?: string;
          p_result_kind: string;
          p_result_status: string;
          p_retry_after_ms?: number;
          p_sanitization_version?: string;
        };
        Returns: {
          exchange_id: string;
          execution_id: string;
          job_id: string;
          job_status: string;
          next_attempt_at: string;
          snapshot_id: string;
        }[];
      };
      phase9_recover_expired_query_jobs: {
        Args: { p_limit?: number };
        Returns: number;
      };
      phase9_renew_query_job_lease: {
        Args: {
          p_execution_id: string;
          p_job_id: string;
          p_lease_duration_ms?: number;
          p_lease_token: string;
        };
        Returns: boolean;
      };
      phase9_request_manual_reprocess: {
        Args: { p_failed_job_id: string; p_idempotency_key: string };
        Returns: string;
      };
      phase9_scheduler_tick: {
        Args: { p_as_of: string; p_window_tolerance_seconds?: number };
        Returns: number;
      };
      phase9_set_process_monitoring_status: {
        Args: { p_process_id: string; p_status: string };
        Returns: undefined;
      };
      phase9_timezone_is_valid: {
        Args: { p_timezone: string };
        Returns: boolean;
      };
      phase9_upsert_monitoring_configuration: {
        Args: {
          p_active: boolean;
          p_office_id: string;
          p_timezone: string;
          p_version: number;
        };
        Returns: string;
      };
      phase9_upsert_monitoring_schedule: {
        Args: {
          p_active: boolean;
          p_configuration_id: string;
          p_days_of_week: number[];
          p_local_time: string;
          p_timezone: string;
        };
        Returns: string;
      };
      phase9_write_system_audit: {
        Args: {
          p_action: string;
          p_entity_id: string;
          p_entity_type: string;
          p_metadata: Json;
          p_office_id: string;
          p_origin: string;
          p_worker_id?: string;
        };
        Returns: number;
      };
      phase9_write_user_audit: {
        Args: {
          p_action: string;
          p_entity_id: string;
          p_entity_type: string;
          p_metadata?: Json;
        };
        Returns: number;
      };
      preview_process_import: {
        Args: {
          p_content_hash: string;
          p_normalized_rows: Json;
          p_parser_version: string;
          p_summary?: Json;
        };
        Returns: {
          expires_at: string;
          preview_id: string;
          summary: Json;
        }[];
      };
      provider_json_has_comparison: {
        Args: { p_value: Json };
        Returns: boolean;
      };
      provider_payload_has_sensitive_key: {
        Args: { p_value: Json };
        Returns: boolean;
      };
      record_invite_audit_internal: {
        Args: {
          p_actor_user_id: string;
          p_outcome: string;
          p_reason?: string;
          p_target_user_id: string;
        };
        Returns: number;
      };
      record_provider_exchange: {
        Args: {
          p_contract_version: number;
          p_correlation_id: string;
          p_error_code?: string;
          p_normalized_result?: Json;
          p_process_id: string;
          p_provider_id: string;
          p_raw_payload?: Json;
          p_received_at?: string;
          p_request_fingerprint: string;
          p_result_kind: string;
          p_result_status: string;
          p_sanitization_version?: string;
          p_source: string;
          p_subject_ref: string;
        };
        Returns: string;
      };
      record_provider_exchange_internal: {
        Args: {
          p_actor_user_id: string;
          p_contract_version: number;
          p_correlation_id: string;
          p_error_code?: string;
          p_normalized_result?: Json;
          p_process_id: string;
          p_provider_id: string;
          p_raw_payload?: Json;
          p_received_at?: string;
          p_request_fingerprint: string;
          p_result_kind: string;
          p_result_status: string;
          p_sanitization_version?: string;
          p_source: string;
          p_subject_ref: string;
        };
        Returns: string;
      };
      record_rejection_audit_internal: {
        Args: {
          p_action: string;
          p_actor_user_id: string;
          p_entity_id: string;
          p_entity_type: string;
          p_reason: string;
        };
        Returns: number;
      };
      reject_client_related_party: {
        Args: { p_relation_id: string };
        Returns: undefined;
      };
      reject_process_party: {
        Args: { p_relation_id: string };
        Returns: undefined;
      };
      require_active_actor: {
        Args: never;
        Returns: {
          actor_id: string;
          actor_is_owner: boolean;
          actor_office_id: string;
          actor_role: Database['public']['Enums']['user_role'];
        }[];
      };
      require_active_owner: {
        Args: never;
        Returns: {
          actor_id: string;
          actor_is_owner: boolean;
          actor_office_id: string;
          actor_role: Database['public']['Enums']['user_role'];
        }[];
      };
      require_provider_actor: {
        Args: { p_actor_user_id: string };
        Returns: {
          actor_id: string;
          actor_is_owner: boolean;
          actor_office_id: string;
          actor_role: Database['public']['Enums']['user_role'];
        }[];
      };
      require_provider_process_eligible: {
        Args: { p_process_id: string };
        Returns: undefined;
      };
      require_provider_process_eligible_internal: {
        Args: { p_actor_user_id: string; p_process_id: string };
        Returns: undefined;
      };
      set_user_active: {
        Args: { p_is_active: boolean; p_target_user_id: string };
        Returns: {
          created_at: string;
          id: string;
          is_active: boolean;
          is_owner: boolean;
          name: string;
          office_id: string;
          role: Database['public']['Enums']['user_role'];
        };
        SetofOptions: {
          from: '*';
          to: 'user_profile';
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      set_user_owner: {
        Args: { p_is_owner: boolean; p_target_user_id: string };
        Returns: {
          created_at: string;
          id: string;
          is_active: boolean;
          is_owner: boolean;
          name: string;
          office_id: string;
          role: Database['public']['Enums']['user_role'];
        };
        SetofOptions: {
          from: '*';
          to: 'user_profile';
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      update_client: {
        Args: { p_id: string; p_status?: string };
        Returns: undefined;
      };
      update_legal_process: {
        Args: {
          p_cnj_number: string;
          p_id: string;
          p_is_public?: boolean;
          p_system?: string;
          p_tribunal: string;
        };
        Returns: undefined;
      };
      update_office_name: {
        Args: { p_name: string };
        Returns: {
          created_at: string;
          id: string;
          is_active: boolean;
          name: string;
        };
        SetofOptions: {
          from: '*';
          to: 'office';
          isOneToOne: true;
          isSetofReturn: false;
        };
      };
      update_party: {
        Args: { p_display_name: string; p_id: string; p_party_type?: string };
        Returns: undefined;
      };
      write_admin_audit: {
        Args: {
          p_action: string;
          p_entity_id: string;
          p_entity_type: string;
          p_metadata?: Json;
        };
        Returns: number;
      };
      write_operational_audit: {
        Args: {
          p_action: string;
          p_entity_id: string;
          p_entity_type: string;
          p_metadata?: Json;
        };
        Returns: number;
      };
      write_provider_audit: {
        Args: {
          p_action: string;
          p_entity_id: string;
          p_entity_type: string;
          p_metadata?: Json;
        };
        Returns: number;
      };
    };
    Enums: {
      user_role: 'lawyer' | 'operator' | 'reviewer' | 'auditor';
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  'public'
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] &
        DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] &
        DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema['CompositeTypes']
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      user_role: ['lawyer', 'operator', 'reviewer', 'auditor'],
    },
  },
} as const;
