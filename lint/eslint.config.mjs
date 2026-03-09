import js from "@eslint/js"
import tseslint from "typescript-eslint"
import prettier from "eslint-config-prettier"

export default [

  js.configs.recommended,

  ...tseslint.configs.recommended,

  {
    files: ["**/*.ts", "**/*.tsx", "**/*.js", "**/*.mjs"],

    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module"
      }
    },

    rules: {
      // NestJS usa muito `any` em filters/interceptors/adapters
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