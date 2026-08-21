export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type DatabaseWithoutInternals = {
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
          operationName?: string;
          query?: string;
          variables?: Json;
          extensions?: Json;
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
            foreignKeyName: 'user_profile_id_fkey';
            columns: ['id'];
            isOneToOne: true;
            referencedRelation: 'users';
            referencedColumns: ['id'];
          },
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
      get_auth_user_profile: {
        Args: Record<PropertyKey, never>;
        Returns: {
          created_at: string;
          id: string;
          is_active: boolean;
          is_owner: boolean;
          name: string;
          office_id: string;
          role: Database['public']['Enums']['user_role'];
        }[];
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

type DatabaseWithoutInternalsPublic = DatabaseWithoutInternals['public'];

export type Database = DatabaseWithoutInternals & {
  public: {
    Tables: DatabaseWithoutInternalsPublic['Tables'];
    Views: DatabaseWithoutInternalsPublic['Views'];
    Functions: DatabaseWithoutInternalsPublic['Functions'];
    Enums: DatabaseWithoutInternalsPublic['Enums'];
    CompositeTypes: DatabaseWithoutInternalsPublic['CompositeTypes'];
  };
};

type DefaultSchema = DatabaseWithoutInternals['public'];

export type Tables<
  PublicTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (PublicTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Views'])
    : never) = never,
> = PublicTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : PublicTableNameOrOptions extends keyof (DefaultSchema['Tables'] &
        DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] &
        DefaultSchema['Views'])[PublicTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  PublicTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (PublicTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = PublicTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : PublicTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][PublicTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  PublicTableNameOrOptions extends
    keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (PublicTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Tables']
    : never) = never,
> = PublicTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : PublicTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][PublicTableNameOrOptions] extends {
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
