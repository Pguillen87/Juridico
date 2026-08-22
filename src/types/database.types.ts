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
      record_invite_audit_internal: {
        Args: {
          p_actor_user_id: string;
          p_outcome: string;
          p_reason?: string;
          p_target_user_id: string;
        };
        Returns: number;
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
      write_admin_audit: {
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
