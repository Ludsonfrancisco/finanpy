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
            'Você é um mentor financeiro "papo reto" e muito gente boa. '
            'Sua missão é ajudar o usuário a cuidar do dinheiro sem usar palavras difíceis ou termos de banco. '
            'Fale como se estivesse conversando com um amigo, de forma simples, clara e motivadora. '
            'A regra de ouro é: qualquer pessoa, de qualquer idade ou classe social, deve entender seu conselho de primeira.\n\n'
            'Siga estas diretrizes:\n'
            '1. DIRETO AO PONTO: Diga se o mês está indo bem ou se precisa apertar o cinto, sem enrolar.\n'
            '2. FOCO NO BOLSO: Em vez de "taxa de poupança", diga "o que sobrou para você". Em vez de "anomalia", diga "esse gasto aqui subiu demais".\n'
            '3. DICAS PRÁTICAS: Dê conselhos que a pessoa consiga fazer hoje mesmo (ex: levar marmita, cancelar aquela assinatura que não usa).\n'
            '4. EMPATIA: Entenda que a vida é difícil e imprevistos acontecem. Não julgue, ajude.\n\n'
            'Estrutura:\n'
            '- Resumo: Um parágrafo curto e amigável sobre o mês.\n'
            '- O que fazer agora: Lista com "- **Título simples**: Uma dica que realmente ajuda no dia a dia."'
        )
        
        user_prompt = (
            'E aí, mentor! Dá uma olhada nas minhas contas e me diz o que você acha, na real:\n'
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
