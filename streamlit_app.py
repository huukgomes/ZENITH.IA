                     import streamlit as st
                     from google import genai

                     # 1. Configuração visual do ZENITH.IA
                     st.set_page_config(page_title="ZENITH.IA", page_icon="🤖")
                     st.title("🤖 ZENITH.IA")

                     # 2. Lógica para ler a chave dos Segredos (Secrets)
                     if "GOOGLE_API_KEY" in st.secrets:
                         client = genai.Client(api_key=st.secrets["GOOGLE_API_KEY"])
                             
                                 # Inicializa o histórico se não existir
                                     if "messages" not in st.session_state:
                                             st.session_state.messages = []

                                                 # Mostra as mensagens salvas na tela
                                                     for message in st.session_state.messages:
                                                             with st.chat_message(message["role"]):
                                                                         st.markdown(message["content"])

                                                                             # Campo para o usuário digitar a pergunta
                                                                                 if prompt := st.chat_input("Olá! Como posso ajudar hoje?"):
                                                                                         st.session_state.messages.append({"role": "user", "content": prompt})
                                                                                                 with st.chat_message("user"):
                                                                                                             st.markdown(prompt)

                                                                                                                     # Resposta da IA (Gemini 2.0 Flash)
                                                                                                                             response = client.models.generate_content(
                                                                                                                                         model="gemini-2.0-flash", 
                                                                                                                                                     contents=prompt
                                                                                                                                                             )
                                                                                                                                                                     
                                                                                                                                                                             with st.chat_message("assistant"):
                                                                                                                                                                                         st.markdown(response.text)
                                                                                                                                                                                                     st.session_state.messages.append({"role": "assistant", "content": response.text})
                                                                                                                                                                                                     else:
                                                                                                                                                                                                         st.error("Erro: A chave GOOGLE_API_KEY não foi encontrada nos Segredos do Streamlit!")
                                                                                                                                                                                         