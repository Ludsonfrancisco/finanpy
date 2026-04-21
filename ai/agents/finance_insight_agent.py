import os
from dataclasses import dataclass
from typing import List

from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser

@dataclass
class AnalysisResult:
    summary: str
    insights: List[str]

class FinanceInsightAgent:
    def __init__(self):
        api_key = os.environ.get('OPENAI_API_KEY')
        self.model = ChatOpenAI(
            model='gpt-5-mini',
            temperature=0.3,
            openai_api_key=api_key
        )
        self.output_parser = StrOutputParser()
        
    def _get_prompt(self):
        system_prompt = (
            'Você é um assistente financeiro pessoal especializado em análise de dados. '
            'Sua tarefa é analisar os dados financeiros do usuário e fornecer um resumo e insights acionáveis. '
            'Responda sempre em português (pt-BR). '
            'A resposta deve ser estruturada da seguinte forma: '
            'Um parágrafo de resumo da situação financeira atual. '
            'Seguido por uma lista de insights (pontos de atenção ou sugestões de melhoria), um por linha, começando com "- ".'
        )
        
        user_prompt = (
            'Aqui estão os dados financeiros para análise:\n'
            '{context}'
        )
        
        return ChatPromptTemplate.from_messages([
            ('system', system_prompt),
            ('user', user_prompt)
        ])

    def analyze(self, context: dict) -> AnalysisResult:
        prompt = self._get_prompt()
        chain = prompt | self.model | self.output_parser
        
        # Converte o dicionário de contexto em uma string formatada para o prompt
        context_str = str(context)
        
        response = chain.invoke({'context': context_str})
        
        return self._parse_response(response)

    def _parse_response(self, response: str) -> AnalysisResult:
        lines = response.strip().split('\n')
        summary_lines = []
        insights = []
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            if line.startswith('- '):
                insights.append(line[2:])
            else:
                if not insights: # Ainda estamos no resumo
                    summary_lines.append(line)
                else:
                    # Se algo vier depois dos insights, ignoramos ou tratamos
                    pass
        
        summary = ' '.join(summary_lines)
        return AnalysisResult(summary=summary, insights=insights)
