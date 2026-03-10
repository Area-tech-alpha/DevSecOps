import js from "@eslint/js"
import tseslint from "typescript-eslint"
import prettier from "eslint-config-prettier"
import globals from "globals"

export default [

  js.configs.recommended,

  ...tseslint.configs.recommended,

  {
    files: ["**/*.ts", "**/*.tsx", "**/*.js", "**/*.mjs", "**/*.jsx"],

    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
        ecmaFeatures: { jsx: true }
      },
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.es2021
      }
    },

    // Configuração "Dummy" do react-hooks para evitar que comentários `// eslint-disable-next-line react-hooks/algo` 
    // em projetos Front-End não crashem o ESLint global por não encontrar a definição da regra no repositório central.
    plugins: {
      "react-hooks": {
        rules: {
          "rules-of-hooks": { create() { return {}; } },
          "exhaustive-deps": { create() { return {}; } }
        }
      }
    },

    rules: {
      // Regras nativas muito restritas do ESLint 9 ou falsos-positivos de legacy code
      "no-empty": "warn",
      "no-useless-assignment": "warn",
      "no-console": "warn",
      "no-shadow": "warn",

      // Segurança
      "no-eval": "error",
      "no-implied-eval": "error",
      "no-new-func": "error",

      // NestJS/Frontends usam muito `any` em filters/interceptors/adapters/props
      // Em vez de "error" que quebra o CI, vira um warning.
      "@typescript-eslint/no-explicit-any": "warn",

      // Permite variáveis não usadas se começarem com underscore 
      // Ex: _source, _totalProducts
      "@typescript-eslint/no-unused-vars": [
        "warn",
        {
          "argsIgnorePattern": "^_",
          "varsIgnorePattern": "^_",
          "caughtErrorsIgnorePattern": "^_"
        }
      ]
    }
  },

  {
    // Scripts do K6 usam variáveis globais específicas e console.log intensamente
    files: ["**/k6/**/*.js"],
    languageOptions: {
      globals: {
        __ENV: "readonly",
        open: "readonly",
        console: "readonly",
        TextEncoder: "readonly"
      }
    },
    rules: {
      "no-undef": "off", // Desliga no-undef para K6 scripts (são injetados pelo runtime do k6)
      "@typescript-eslint/no-unused-vars": "warn"
    }
  },

  {
    ignores: [
      "dist",
      "node_modules",
      "coverage"
    ]
  },

  prettier
]